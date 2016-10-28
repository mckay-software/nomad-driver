#!/usr/bin/env ruby

require_relative 'bundle/bundler/setup'
require 'slop'
require_relative 'ext/slop'

opts = Slop.parse do |o|
  o.separator "Options:"

  o.multi '-a', '--alias', 'additional network alias'
  o.separator ''

  o.multi '-p', '--port', 'port to expose, format name[:number]'
  o.null 'If number is not supplied, it will be derived from the name'
  o.null 'e.g. `--port http` is equivalent to `--port http:80`.'
  o.separator ''

  o.banner = 'Usage: driver/main.rb [options] <image> [-- arguments]'
  o.bool '-h', '--help', 'this help message'
end

if opts.help? or opts.arguments.count < 1
  puts opts
  exit 1
end

image = opts.arguments.shift


# Docker option list
options = [
  # Use the pan-cluster network
  '--network=overlay',

  # Imitate Nomad naming scheme
  "--name=#{ENV['NOMAD_TASK_NAME']}-#{ENV['NOMAD_ALLOC_ID']}",

  # Set resource limits
  "--cpu-shares=#{ENV['NOMAD_CPU_LIMIT']}",
  "--memory=#{ENV['NOMAD_MEMORY_LIMIT']}m",

  # Bind nomad task and alloc dirs
  "--volume=#{ENV['NOMAD_ALLOC_DIR']}:/alloc",
  "--volume=#{ENV['NOMAD_TASK_DIR']}:/local",
]

# Parse Job/Group/Task/ID
(job, group) = ENV['NOMAD_ALLOC_NAME'].split('.')
group = group.split('[').first
task = ENV['NOMAD_TASK_NAME']
id = ENV['NOMAD_ALLOC_INDEX']

# Assign them to env
ENV['NOMAD_JOB_NAME'] = job
ENV['NOMAD_GROUP_NAME'] = group

# Copy env to options
ENV.each do |key, value|
  next if key == 'PATH'
  next if key == 'LANG'
  options << "--env"
  options << "#{key}=#{value}"
end

# Derive port from a name
def derive_port name
  begin
    Socket.getservbyname name
  rescue SocketError
    nil
  end
end

# Expose ports as needed
(opts[:port] || []).each do |couple|
  (name, port) = couple.split(':')

  # Skip if the port isn't in NOMAD_PORT_*
  next if ENV["NOMAD_PORT_#{name}"].empty?

  # Try to derive, but skip if we can't
  port = derive_port name unless port
  next unless port

  options << "--publish"
  options << "#{ENV["NOMAD_PORT_#{name}"]}:#{port}"
end

# Automatic service network aliases
[job, group, task, "n#{id}"].reduce([]) do |memo, name|
  memo << name
  options << "--network-alias=#{memo.reverse.join('.')}"
  memo
end

# Additional network aliases
(opts[:alias] || []).each do |name|
  options << "--network-alias=#{name}"
end

puts "/usr/bin/docker", "run", "--rm", *options, image, *opts.arguments
exec "/usr/bin/docker", "run", "--rm", *options, image, *opts.arguments
