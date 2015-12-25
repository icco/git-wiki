require 'rubygems'
require 'bundler'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

module GitWiki
  class << self
    attr_accessor :homepage, :extension, :repository
  end

  def self.new(repository, extension, homepage)
    self.homepage   = homepage
    self.extension  = extension
    self.repository = Rugged::Repository.new(repository)

    App
  end

  class PageNotFound < Sinatra::NotFound
    attr_reader :name

    def initialize(name)
      @name = name
    end
  end

  class Page
    def self.find_all
      repository.head.target.tree
    end

    def self.find(name)
      page_blob = find_blob(name)
      fail PageNotFound.new(name) unless page_blob
      new(page_blob, name)
    end

    def self.find_or_create(name)
      find(name)
    rescue PageNotFound
      new(commit_blob(name), name)
    end

    def self.css_class_for(name)
      find(name)
      'exists'
    rescue PageNotFound
      'unknown'
    end

    def self.repository
      GitWiki.repository || fail
    end

    def self.extension
      GitWiki.extension || fail
    end

    def self.find_blob(page_name)
      filename = page_name + extension
      o = repository.head.target.tree.find { |o| o[:name].eql? filename }
      return o.nil? ? nil : o[:oid]
    end
    private_class_method :find_blob

    def self.commit_blob(page_name, content = '')
      oid = repository.write(content, :blob)
      index = repository.index
      index.read_tree(repository.head.target.tree)
      index.add(path: page_name + extension, oid: oid, mode: 0100644)

      options = {}
      options[:tree] = index.write_tree(repository)

      options[:author] = { email: 'testuser@github.com', name: 'Test Author', time: Time.now }
      options[:committer] = { email: 'testuser@github.com', name: 'Test Author', time: Time.now }
      options[:message] ||= 'Making a commit via Rugged!'
      options[:parents] = repository.empty? ? [] : [repository.head.target].compact
      options[:update_ref] = 'HEAD'

      Rugged::Commit.create(repository, options)

      return oid
    end

    def initialize(blob, name)
      @name = name
      @blob = Page.repository.lookup(blob)
    end

    def to_html
      RDiscount.new(wiki_link(content)).to_html
    end

    def to_s
      name
    end

    def new?
      @blob.id.nil?
    end

    def name
      @name.gsub(/#{File.extname(@name)}$/, '')
    end

    def content
      @blob.content
    end

    def update_content(new_content)
      return if new_content == content
      Page.commit_blob(@name, new_content)
    end

    private

    def file_name
      File.join(self.class.repository.workdir, name + self.class.extension)
    end

    def commit_message
      new? ? "Created #{name}" : "Updated #{name}"
    end

    def wiki_link(str)
      str.gsub(/([A-Z][a-z]+[A-Z][A-Za-z0-9]+)/) { |page|
        %(<a class="#{self.class.css_class_for(page)}") +
          %(href="/#{page}">#{page}</a>)
      }
    end
  end

  class App < Sinatra::Base
    set :app_file, __FILE__
    set :haml, { format: :html5,
                 attr_wrapper: '"' }
    enable :inline_templates

    error PageNotFound do
      page = request.env['sinatra.error'].name
      redirect "/#{page}/edit"
    end

    before do
      content_type 'text/html', charset: 'utf-8'
    end

    get '/' do
      redirect '/' + GitWiki.homepage
    end

    get '/pages' do
      @pages = Page.find_all
      haml :list
    end

    get '/:page/edit' do
      @page = Page.find_or_create(params[:page])
      haml :edit
    end

    get '/:page' do
      @page = Page.find(params[:page])
      haml :show
    end

    post '/:page' do
      @page = Page.find_or_create(params[:page])
      @page.update_content(params[:body])
      redirect "/#{@page}"
    end

    private

    def title(title = nil)
      @title = title.to_s unless title.nil?
      @title
    end

    def list_item(page)
      %(<a class="page_name" href="/#{page}">#{page.name}</a>)
    end
  end
end

__END__
@@ layout
!!!
%html
  %head
    %title= title
  %body
    %ul
      %li
        %a{ :href => "/#{GitWiki.homepage}" } Home
      %li
        %a{ :href => "/pages" } All pages
    #content= yield

@@ show
- title @page.name
#edit
  %a{:href => "/#{@page}/edit"} Edit this page
%h1= title
#content
  ~"#{@page.to_html}"

@@ edit
- title "Editing #{@page.name}"
%h1= title
%form{:method => 'POST', :action => "/#{@page}"}
  %p
    %textarea{:name => 'body', :rows => 30, :style => "width: 100%"}= @page.content
  %p
    %input.submit{:type => :submit, :value => "Save as the newest version"}
    or
    %a.cancel{:href=>"/#{@page}"} cancel

@@ list
- title "Listing pages"
%h1 All pages
- if @pages.empty?
  %p No pages found.
- else
  %ul#list
    - @pages.each do |page|
      %li= list_item(page)
