#!/usr/bin/env ruby

$: << 'lib'
require "zbx-api.rb"

zbx = Lvp::Zbx.new
version = zbx.version

puts "Zabbix API version is #{version}"
