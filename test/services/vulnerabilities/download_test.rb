require "test_helper"

class Vulnerabilities::DownloadTest < ActiveSupport::TestCase
  include HttpsServerHelpers
  include TcpHelpers

  HANDLER = lambda do |_method, path, _headers|
    case path
    when "/feed" then "HTTP/1.1 302 Found\r\nLocation: /data.json\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    when "/data.json" then "HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\n{\"a\": 1}"
    when "/big" then "HTTP/1.1 200 OK\r\nContent-Length: 2000\r\nConnection: close\r\n\r\n#{"x" * 2000}"
    else "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    end
  end

  test "downloads to a temporary file, following a redirect, removed afterwards" do
    with_https_server(Vulnerabilities::Download, handler: HANDLER) do |host|
      kept = nil
      Vulnerabilities::Download.open("https://#{host}/feed") do |path|
        kept = path
        assert_equal %({"a": 1}), File.read(path)
      end
      assert_not File.exist?(kept)
    end
  end

  test "an HTTP error, a file too big, a plain HTTP address" do
    with_https_server(Vulnerabilities::Download, handler: HANDLER) do |host|
      error = assert_raises(Vulnerabilities::Error) { Vulnerabilities::Download.open("https://#{host}/missing") { } }
      assert_match "HTTP 404", error.message
      assert_raises(Vulnerabilities::Error) { Vulnerabilities::Download.open("https://#{host}/big", max_size: 1000) { } }
    end
    assert_match "HTTPS seulement", assert_raises(Vulnerabilities::Error) { Vulnerabilities::Download.open("http://example.com/feed") { } }.message
  end

  test "checks that a feed answers without downloading it (HEAD, a redirect is an answer)" do
    with_https_server(Vulnerabilities::Download, handler: HANDLER) do |host, requests|
      assert_nil Vulnerabilities::Download.check("https://#{host}/feed")
      assert_equal "HEAD", requests.pop.first
      assert_match "HTTP 404", assert_raises(Vulnerabilities::Error) { Vulnerabilities::Download.check("https://#{host}/missing") }.message
    end
    assert_match "HTTPS seulement", assert_raises(Vulnerabilities::Error) { Vulnerabilities::Download.check("http://example.com/feed") }.message
    assert_raises(Vulnerabilities::Error) { Vulnerabilities::Download.check("https://127.0.0.1:#{closed_port}/feed") }
  end
end
