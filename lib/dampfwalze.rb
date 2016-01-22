# dampfwalze.rb
#
# Copyright (c) 2016 William C. Benton and Red Hat, Inc.
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'octokit'
require 'open3'
require 'curl'

module Dampfwalze

  module ProcessHelpers
    def spawn_and_capture(*cmd)
      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
        exit_status = wait_thr.value
        raise "command '#{cmd.inspect}' failed; more details follow:  #{stderr.read}" unless exit_status == 0
        stdout.read
      end
    end

    def spawn_with_input(str, *cmd)
      out, err, s = Open3.capture3(*cmd, :stdin_data=>str)
      raise "command '#{cmd.inspect}' failed; more details follow:  #{err}" unless s.exitstatus == 0
      [out, err]
    end
  end
  
  class CommitMeta
    attr_reader :author, :sha, :message

    def initialize(sha, author, message)
      @sha = sha
      @author = "#{author[:name]} <#{author[:email]}>"
      @message = message || ""
    end

    def summary(prefix="", suffix="")
      "#{prefix}#{@sha.slice(0,8)} #{@message.split('\n')[0]}#{suffix}"
    end
  end
  
  class PRMeta
    attr_reader :number, :user, :patch_url, :commits_url, :pr, :title, :body
    
    def initialize(pr)
      @pr = pr
      @user = pr.user
      @number = pr.number
      @title = pr.title
      @body = pr.body
      @patch_url = pr.patch_url
      @commits_url = pr.commits_url
    end

    def commits
      @pr.rels[:commits].get.data.map do |c|
        CommitMeta.new(c.sha, c.commit.author, c.commit.message)
      end
    end

    def authorCounts
      commits.map {|c| c.author}.inject(Hash.new(0)) do |hash, k|
        hash[k] += 1
        hash
      end
    end
    
    def primaryAuthor
      authorCounts.sort_by {|k,v| -v}.map{|k,v| k}[0]
    end

    def mergeMessage
      summary = commits.map {|c| c.summary(" * ")}.join("\n")
      <<eos
#{@title}

#{@body}

Closes ##{@number} and squashes the following commits:

#{summary}
eos
    end

    def patch
      status = "3"
      url = patch_url
      
      while status[0] == "3"
        easy = Curl::Easy.perform(url)
        status = easy.status
        url = easy.redirect_url
      end

      easy.body_str
    end
    
    def doCommit
      # curl -L #{pr.patch_url} | git apply --index
      # echo #{pr.mergeMessage} | git commit --author #{pr.primaryAuthor} --signoff -t -
      git = Config.options[:git_binary] || "/usr/bin/git"
      spawn_with_input(patch, [git, "apply", "--index"])
      spawn_with_input(mergeMessage, [git, "commit", "--author", pr.primaryAuthor, "--signoff", "-F", "-"])
    end

    include ProcessHelpers
  end 
  
  class GHSession
    def initialize(username, pw)
      @client = Octokit::Client.new(:login => username, :password => pw)
    end
    
    def pr(repo, number)
      result, = @client.repo(repo).rels[:pulls].get.data.select { |p| p.number == number }
      PRMeta.new(result)
    end
  end

  module Config
    class << self
      attr_reader :options
    end
    
    def self.set(options)
      @options = options.clone.freeze
      @options
    end
  end
end
