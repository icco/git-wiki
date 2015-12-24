#!/usr/bin/env rackup

require File.dirname(__FILE__) + "/git-wiki"

git_dir = File.expand_path(ARGV[1] || "~/Projects/wiki")
extension = ARGV[2] || ".md"
home =  ARGV[3] || "Home"

run GitWiki.new(git_dir, extension, home)
