require "kemal"
require "redis"
require "digest"
require "json"

TLS_CONFIG = begin
  tls = OpenSSL::SSL::Context::Client.new
  if ENV.has_key?("SSL_CERT_PATH")
    tls.ca_certificates = ENV["SSL_CERT_PATH"]
  end
  tls
end

REDIS_POOL = begin
  if ENV.has_key?("REDIS_URL")
    Redis::PooledClient.new url: ENV["REDIS_URL"]
  else
    Redis::PooledClient.new
  end
end

def set_key_ttl(key, value, ttl)
  REDIS_POOL.set(key, value)
  REDIS_POOL.expire(key, ttl)
end

def proxy(method, url, headers, body)
  headers.delete("X-REQUEST-URL")
  headers.delete("Connection")
  headers.delete("Host")
  HTTP::Client.exec(method, url, headers: headers, body: body, tls: TLS_CONFIG)
end

def do_proxy(method, env : HTTP::Server::Context)
  url = env.request.headers["X-REQUEST-URL"]

  save_cache = ->(response : HTTP::Client::Response) {}

  if env.request.headers.has_key?("X-CACHE-EXPIRE")
    url_hex = Digest::MD5.hexdigest(url)
    body_hex = Digest::MD5.hexdigest(env.request.body.to_s)

    cache_key = Digest::MD5.hexdigest("#{url_hex}.#{body_hex}")

    body_key = "#{cache_key}:body"
    status_code_key = "#{cache_key}:code"

    body = REDIS_POOL.get(body_key)
    status_code = REDIS_POOL.get(status_code_key)

    if !body.nil? && !status_code.nil?
      env.response.headers.merge!({"X-IS-CACHE" => "true"})
      env.response.status_code = status_code.to_i
      return body
    else
      ttl = env.request.headers["X-CACHE-EXPIRE"].to_i
      save_cache = ->(response : HTTP::Client::Response) {
        set_key_ttl(body_key, response.body.to_s, ttl)
        set_key_ttl(status_code_key, response.status_code, ttl)
      }
    end
  end

  response = proxy(method, url, env.request.headers, env.request.body)
  env.response.headers.merge! response.headers
  env.response.status_code = response.status_code

  save_cache.call(response)

  response.body
end

get "/proxy" do |env|
  do_proxy("GET", env)
end

post "/proxy" do |env|
  do_proxy("POST", env)
end

put "/proxy" do |env|
  do_proxy("PUT", env)
end

patch "/proxy" do |env|
  do_proxy("PATCH", env)
end

delete "/proxy" do |env|
  do_proxy("DELETE", env)
end

Kemal.config.port = ENV.fetch("PORT", "3000").to_i
Kemal.run
