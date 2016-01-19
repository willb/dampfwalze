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
require 'git'

module Dampfwalze
  class CommitMeta
    attr_reader :author, :sha, :message

    def initialize(sha, author, message)
      @sha = sha
      @author = author
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
        CommitMeta.new(c.sha, c.author, c.message)
      end
    end

    def mergeMessage
      summary = commits.map {|c| c.summary(" * ")}.join('\n')
      git_config = Git.open(".").config
      git_user = "#{git_config["user.name"]} <#{git_config["user.email"]}>"
      <<eos
#{@title}

#{@body}

Closes ##{@number} and squashes the following commits:

#{summary}

Signed-off-by: #{git_user}
eos
    end
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
end
