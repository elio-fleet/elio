# A text kept to be written in the language of whoever reads it (the label
# of a run, the result of an automation): an I18n key and its parameters,
# stored as JSON in a text column, translated when read. A parameter can be
# a text itself (part). Plain strings (older rows, texts built elsewhere)
# are read as they are.
#
#   LocalizedText.dump("automation.results.inventoried", done: 8, count: 8)
#   LocalizedText.render(value) # => "8/8 serveurs inventoriés" in French
module LocalizedText
  PREFIX = '{"key":'

  def self.part(key, **params) = { "key" => key.to_s, "params" => params.stringify_keys }

  def self.dump(key, **params) = part(key, **params).to_json

  def self.render(value)
    return value unless value.is_a?(String) && value.start_with?(PREFIX)

    translate(JSON.parse(value))
  rescue JSON::ParserError
    value
  end

  def self.translate(data)
    params = data["params"].to_h.to_h { |name, param| [ name.to_sym, param.is_a?(Hash) && param["key"] ? translate(param) : param ] }
    I18n.t(data["key"], **params)
  end
  private_class_method :translate
end
