#!/usr/bin/env ruby
#
# Get all nodes from chef, 
# Based on roles generate a list of templates and hostgroups for each node
# Create/Update node.
#

$: << 'lib'
require "zbx-api.rb"
require 'chef'                                                                  

zbx = Lvp::Zbx.new

# Obtain Chef nodes:
creds = zbx.creds
chef_url = creds["chef"]["chef_url"]              
client = creds["chef"]["client"]                                                                 
key_filename="#{ENV["HOME"]}/.chef/paha.pem"                                    
api = Chef::REST.new(chef_url, client, key_filename)                            

# this will take awhile (~7 sec for our 200 nodes).
# use a better search query for more special needs.
puts "Getting chef nodes. #{Time.now}" 
nodes = api.get_rest("search/node")["rows"]
puts "Got #{nodes.size} nodes. #{Time.now}"

# Will add nodes only from specific environments:
supported_env = [ "production", "staging", "dev" ]
# Few roles to ignore:
role_exceptions = [ "monitorable", "cloudkick" ]

nodes.each do |node|
  next unless supported_env.include?(node.chef_environment)
  # puts node.name # debug

  # The node would have to be in folowing groups:
  # ** if env is production do not append it
  groups = []
  # 1. env_location (production_iad)
  pop, env = node.name.split(".")[1], node.chef_environment
  groups << [env, pop].join("_").gsub("production_","")
  # 2. env_location_role (production_iad_transcoder)
  # 3. env_role (production_iad) 
  node.roles.each do |role|
    next if role_exceptions.include?(role) or role == "base" or supported_env.include?(role)
    groups << [env, pop, role].join("_").gsub("production_","")
    groups << [env, role].join("_").gsub("production_","")
  end
  
  # puts groups # debug

  my_groups = [] # thes just the groupids for the zbx.node object.
  groups.each do |group|
    groupid = zbx.group_map[group]
    my_groups << { "groupid" => groupid }
    # insure group exists, creat if needed.
    zbx.hostgroup_add(group) unless zbx.group_map.keys.include?(group)
  end

  # It also would have to be linked to following templates:
  my_templates = []
  # template_role (template_activemq)
  node.roles.each do |role|
    next if role_exceptions.include?(role) or supported_env.include?(role)
    template = "template_" + role
    zbx.template_add(template) unless zbx.template_map.keys.include?(template)
    id = zbx.template_map[template]
    my_templates << { "templateid" => id }
    # puts template # debug
  end

  # here we go
  if zbx.exists?(node.name)
    zbx.host_add_chef(node,my_groups,my_templates,"update")
  else
    zbx.host_add_chef(node,my_groups,my_templates)
  end
  
end
