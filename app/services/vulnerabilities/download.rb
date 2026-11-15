require "net/http"

# Downloads a vulnerability feed to a temporary file, streamed (never whole
# in memory): HTTPS only, a few redirects, size capped. Conditional when the
# validators of the previous download are given (ETag, Last-Modified): a file
# that has not changed is not downloaded again.
module Vulnerabilities::Download
  MAX_SIZE = 1.gigabyte
  MAX_REDIRECTS = 3
  NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout ].freeze

  # Trusted certificates (nil: the system's); tests trust a local server.
  mattr_accessor :cert_store

  # Yields the path of the downloaded file (removed afterwards) and the
  # validators of the answer ({ "etag" => …, "last_modified" => … }) to send
  # next time. Returns :not_modified, without yielding, when the server says
  # the file has not changed since `validators`.
  def self.open(url, max_size: MAX_SIZE, validators: nil)
    Tempfile.create([ "elio-feed", File.extname(URI(url).path) ], binmode: true) do |file|
      received = fetch(URI(url), file, max_size, MAX_REDIRECTS, conditions(validators))
      return :not_modified if received == :not_modified

      file.flush
      yield file.path, received
    end
  end

  def self.conditions(validators)
    validators = validators.to_h
    { "If-None-Match" => validators["etag"], "If-Modified-Since" => validators["last_modified"] }.compact_blank
  end

  def self.fetch(uri, file, max_size, redirects, conditions = {})
    raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.https_only", uri: uri) unless uri.is_a?(URI::HTTPS)

    Net::HTTP.start(uri.host, uri.port, **options(read_timeout: 120)) do |http|
      http.request(Net::HTTP::Get.new(uri, { "User-Agent" => "Elio" }.merge(conditions))) do |response|
        case response
        when Net::HTTPNotModified # a 3xx: before the redirections
          return :not_modified
        when Net::HTTPRedirection
          raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.too_many_redirects", uri: uri) if redirects.zero?

          return fetch(URI.join(uri, response["location"]), file, max_size, redirects - 1, conditions)
        when Net::HTTPSuccess
          size = 0
          response.read_body do |chunk|
            size += chunk.bytesize
            raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.too_large", megabyte: (max_size / 1.megabyte)) if size > max_size

            file.write(chunk)
          end
          return { "etag" => response["etag"], "last_modified" => response["last-modified"] }.compact_blank
        else
          raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.http_error", code: response.code, uri: uri)
        end
      end
    end
  rescue *NETWORK_ERRORS => e
    raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.failed", truncate: (e.message.truncate(120)))
  end

  # Checks that a feed answers, without downloading it: a HEAD request, where
  # a redirect counts as an answer (bin/elio-doctor). Raises Vulnerabilities::Error.
  def self.check(url)
    uri = URI(url)
    raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.https_only", uri: uri) unless uri.is_a?(URI::HTTPS)

    Net::HTTP.start(uri.host, uri.port, **options(read_timeout: 15)) do |http|
      response = http.head(uri.request_uri, "User-Agent" => "Elio")
      unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
        raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.http_error", code: response.code, uri: uri)
      end
    end
  rescue *NETWORK_ERRORS => e
    raise Vulnerabilities::Error, I18n.t("vulnerabilities.download.failed", truncate: (e.message.truncate(120)))
  end

  def self.options(read_timeout:)
    { use_ssl: true, open_timeout: 15, read_timeout: read_timeout, cert_store: cert_store }.compact
  end
  private_class_method :options
  private_class_method :conditions
end
