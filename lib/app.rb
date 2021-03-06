require 'config'
require 'webapi/data'
require 'webapi/user'
require 'sinatra/base'

class RotaApp < Sinatra::Base
  set :views, Rota::ViewsDir
  set :public, Rota::PublicDir
  set :root, Rota::RootDir
  
  set :sessions, true
  set :method_override, true
  
  mime_type :xml, 'text/xml'
  mime_type :json, 'application/json'
  mime_type :ical, 'text/calendar'
  mime_type :plain, 'text/plain'

  get '/' do
		redirect 'https://github.com/arekinath/uqrota/wiki/HTTPS-API-Reference'
	end

  use DataService
  use UserService
end
