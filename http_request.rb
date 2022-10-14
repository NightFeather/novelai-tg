require 'net/https'

def send_http_request http_method, uri, content, headers = {}
  if http_method == :post_multipart
    req = Net::HTTP::Post.new uri, headers
    req.set_form content.compact.transform_keys(&:to_s)
    req['Content-Type'] = 'multipart/form-data'
    Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: req.uri.scheme == 'https') { |http| http.request req }
  elsif http_method == :post_form
    req = Net::HTTP::Post.new uri, headers
    req.set_form content.compact.transform_keys(&:to_s)
    Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: req.uri.scheme == 'https') { |http| http.request req }
  else
    Net::HTTP.send(http_method, uri, content, headers)
  end
end

