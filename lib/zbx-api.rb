#!/usr/bin/env ruby
#
# Zabbix API library
# To facilitate interaction with Zabbix server
#

require "net/https"
require "json"
require "resolv"

module Lvp
  VERSION = "0.0.1"

  CREDS_FILE = "secrets.json" unless defined?(CREDS_FILE)
  DEBUG = true unless defined?(DEBUG)

  def creds                                                                     
    return creds = JSON.parse(File.read(CREDS_FILE))                            
    rescue                                                                      
    raise "ERROR: faild to read creds from #{CREDS_FILE}"                       
  end
  
  class Lvp::Zbx
    include Lvp
    attr_reader :group_map, :template_map

    def initialize(url="zabbix.delve.me")
      @id   = 0
      @auth = nil
      @url  = "https://#{url}/api_jsonrpc.php"

      # FIXME: authenticating here. bad
      creds = self.creds
      self.auth(creds["zabbix"]["user"], creds["zabbix"]["passwd"])
    end

    # Creates json request body
    def req_body(method,params={})
      return req = {
        "jsonrpc" =>  "2.0",
        "method"  =>  method,
        "params"  =>  params,
        "auth"    =>  @auth,
        "id"      =>  @id
      }.to_json
    end

    # Send api request
    # Returns Net::HTTP object (temporarely, need to implement error handling, debuging, etc.)
    def api_request(body)
      uri = URI.parse(@url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Post.new(uri.request_uri)
      request.add_field('Content-Type', 'application/json-rpc')
      request.body = body
      
      # increment the request id
      @id+=1
      # returnng entire responce. Will think of how to hadle errors and what to return later.
      return response = http.request(request)
    end

    def version
      body_json = req_body("apiinfo.version")
      return JSON.parse(api_request(body_json).body)["result"]
    end

    # Authenticating to zabbxi api, returns auth token
    def auth(user,passwd)
      body_json = req_body( "user.authenticate", { "user" => user, "password" => passwd })
      responce = api_request(body_json)
      # return authentication token
      # TODO: Check for errors
      return @auth = JSON.parse(responce.body)["result"]
      raise "Failed to authenticate to #{@url}" if @auth.nil?
    end

    # Get a list of Hostgroups.
    # Returning a hash of name=>id
    def get_groups
      body_json = req_body("hostgroup.get", {"output"=>"extend"})
      res = JSON.parse(api_request(body_json).body)["result"]
      groups = {}
      res.each {|g| groups[g["name"]] = g["groupid"]}
      return @group_map = groups
    end
    
    # Get a list of templates
    def get_templates
      body_json = req_body("template.get", {"output"=>"extend"})
      res = JSON.parse(api_request(body_json).body)["result"]
      templates = {}
      res.each {|t| templates[t["host"]] = t["hostid"]}
      return @template_map = templates
    end

    # Adding host, based on Chef node object.
    # identifying pop, and roles should be happening elsewhare.
    def add_host_chef(node, group_ids=[], template_ids=[])
      name = node.name
      return "The node #{name} already is in zabbix." if self.exists?(name)
      # or node.ip ?
      ip = Resolv.getaddress(name)
    
      # @group_map = get_groups if self.group_map.nil?
      # @template_map = get_templates if self.template_map.nil?

      # pop = name.split(".")[1]
      # env = node.chef_environment
      # group_ids << {"groupid" => @group_map["#{pop}_#{env}"]}
      # node.roles.each { |role| template_ids << {"templateid" => @template_map["template_#{role}"]} }
      # pretend we got roles
      # template_ids << {"templateid" => @template_map["template_linux_base"]}
      
      # get the environment
      # TODO: generate params separatly
      # TODO: generate extended node params for inventory, all the data is in chef node object
      params = {
        "host"  => name,
        "dns"   => name,
        "ip"    => ip,
        "port"  => 10050,
        "useip" => 0,
        "groups" => group_ids,
        "templates" => template_ids
      }
      
      puts "Adding node: #{name}" if DEBUG 
      body_json = req_body("host.create", params)
      return JSON.parse(api_request(body_json).body)
    end

    # Examples:
    # a host - self.get_host("vps-099.iad.llnw.net")
    # two hosts - self.get_host("vps-001.iad.llnw.net vps-099.iad.llnw.net")
    # FIXME: search wildcard is not working...
    # all hosts that bellong to a tempalte id - self.get_host(10063,"templateids")
    # all hosts in a hostgroup id - self.get_host(16,"groupids") 
    def get_host(str,type="host")
      case type
      when "host"
        params = {
          "searchWildcardsEnabled" => 1,
          "filter" => { type => str.to_s.split(" ")}
        }
      else
        params = { type => str }
      end
      params["output"] = "extend"
      # NOTE: the results will include dummy hosts...
      # params["excludeSearch"] = "*dummy*"
      body_json = req_body("host.get", params)
      return JSON.parse(api_request(body_json).body)["result"]
    end

    # Test if host, tempalte or hostgroup exists (probably could be used for other objects).
    # Examples:
    # test a host - self.exists?("vps-001.iad.llnw.net")
    # test a template - self.exists?("template_activemq", "template")
    # test a hostgroup - self.exists?("iad_staging", "hostgroup", "name")
    def exists?(name, type="host", str="host")
      body_json = req_body("#{type}.exists", {str => name})                     
      return JSON.parse(api_request(body_json).body)["result"]             
    end

    # add an empty tempalte, we will get some complexity a bit later
    def add_template(name)
      params = {
        "host" => name,
        "groups" => [ {"groupid" => self.group_map["Templates_llnw"]} ]
      }
      
      puts "Adding template: #{name}" if DEBUG 

      body_json = req_body("template.create", params)
      return JSON.parse(api_request(body_json).body)["result"]
    end

    # add a hostgroup
    def add_hostgroup(name)
      puts "Adding hostgroup: #{name}" if DEBUG 
      body_json = req_body("hostgroup.create", {"name" => name})
      return JSON.parse(api_request(body_json).body)["result"]
    end

  end
                                                                            
end