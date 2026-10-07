# Fail closed at startup, before accepting authentication requests.
require Rails.root.join('lib/json_web_token').to_s

JsonWebToken.secret_key
