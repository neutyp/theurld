class LinksController < ApplicationController
  
  def view
    @link = Link.find_by_code(params[:code])
    redirect_to @link.uri
  end
  
  def new
    if request.post?
      require 'net/http'
      require 'hpricot'
      require 'open-uri'
      
      @category = Category.find(params[:category][:id]) unless params[:category][:id].length < 1
      
      case params[:link][:quick]
      when "true"
        # save the Link directly
        add_link(params[:link][:uri])
        
        if @successful
          flash[:notice] = "URL added successfully"
        else
          params[:link].delete('quick')
          @link = Link.new(params[:link])
          flash[:error] = "An error occured while adding your URL. Please try again."
        end
        
        redirect_to session[:referrer] || '/' and return
        
      else
        # create a new LinkQueue with all the URLs
        @queue = LinkQueue.new
        @queue.member_id = @master_member.id
        @queue.uris = []
        
        params[:link][:uri].each_line do |uri|
          uri = uri.strip.chomp
          @queue.uris << uri if uri.length > 0
        end
        
        @queue.size = @queue.uris.length
        
        if @queue.size > 0
          @queue.uris = YAML.dump(@queue.uris)
                    
          if @queue.save
            flash[:notice] = "URL Queue created successfully"
            redirect_to :action => 'queue', :id => @queue.id
          else
            @link = Link.new(params[:link])
            flash[:error] = "A problem occured while creating the URL Queue. Please try again."
          end
        else
          @link = Link.new(params[:link])
          flash[:error] = "It doesn't look like you have any URLs to add&hellip;"
        end
      end
    end
  end
  
  def queue
    # one after another, waiting for the prior links to process before moving on,
    # urls are added with process_url via ajax
    
    @queue = LinkQueue.find(params[:id])
    @queue.uris = YAML.load(@queue.uris)
    
    # run the javascript when the page loads
    # this function is loaded in queue.js
    # 
    # NOTE: Using setTimout will let the page load before running;
    #       In Safari at least, the progress bar will remain loading while
    #       the URLs are added, so this will fix that.
    # 
    # @queue.size needs to be lowered by one because index starts with 0
    @onload = "setTimeout('addLink(#{@queue.id}, 0, #{@queue.size})', 0);"
  end
  
  def process_queue
    # :action => 'queue' uses this to add links
    # accessed via ajax
    
    @queue = LinkQueue.find(params[:id])
    @queue.uris = YAML.load(@queue.uris)
    uri = @queue.uris[params[:index].to_i]
    
    add_link(uri)
    
    # I'm not sure how to get onFailure working yet
    render :nothing => true
  end
  
  private
  
  def add_link(uri)
    uri = uri.strip.chomp
    
    if uri.length > 0 and uri != "http://"
      scheme = URI.parse(uri).scheme
      if scheme == nil
        uri = "http://" + uri
        scheme = "http"
      end
      if scheme.downcase != "http"
        flash[:error] = "Sorry, only HTTP URIs are currently supported."
        return redirect_to(session[:referrer] || '/')
      end
      uri = URI.parse(uri)

      response = Net::HTTP.new(uri.host).request_head((uri.path.length > 0 ? uri.path : "index"))

      if response == 404
        flash[:error] = "Looks like that page doesn't exist!"
        return redirect_to session[:referrer] || '/'
      else
        @domain = Domain.find(:first,
                              :conditions => ['scheme = ? and domain = ?', uri.scheme, uri.host])
        if @domain
          get_favicon(@domain) unless @domain.favicon?
        else
          add_domain(uri)
        end
        
        @link = Link.find(:first,
                          :conditions => ['uri = ?', uri.to_s])
        
        if @link
          unless @link.members.include?(@master_member)
            @link.update_attribute("latest_on", Time.now)
            @master_member.links << @link
          end
        else
          # logger.info "====== Adding new URL: #{uri}"
          @link = Link.new
          @link.domain_id = @domain.id
          @link.category_id = @category ? @category.id : nil
          # images won't return a title, so filename is used
          # hopefully we can come up with a better method
          begin
            document_html = Hpricot(open(uri, "User-Agent" => "theurld"))
            title = document_html.search("title").html.strip
            @link.title = title.length > 0 ? title : File.basename(uri.to_s)
          rescue
            @link.title = File.basename(uri.to_s)
          end

          @link.title = File.basename(uri.to_s) unless @link.title.length > 0
          @link.uri = uri.to_s
          @link.path = uri.path.to_s
          @link.code = generate_code(5)
          @link.latest_on = Time.now

          if @link.save
            @successful = true
            
            @master_member.links << @link
            
            @master_member.update_attribute('number_of_links', @master_member.number_of_links + 1)
            @domain.update_attribute('number_of_links', @domain.number_of_links + 1)
            @link.category.update_attribute('number_of_links', @link.category.number_of_links + 1) if @category
          end
        end
      end
    end
  end
  
  def add_domain(uri)
    # logger.info "=== Adding new domain: #{uri.host}"
    @domain = Domain.new
    
    begin
      document_html = Hpricot(open(uri.host, "User-Agent" => "theurld"))
      title = document_html.search("title").html.strip
      @domain.title = title.length > 0 ? title : File.basename(uri.to_s)
    rescue
      @domain.title = File.basename(uri.to_s)
    end
    
    @domain.title = uri.host unless @domain.title.length > 0
    @domain.scheme = uri.scheme
    @domain.domain = uri.host
    @domain.save
    
    get_favicon(@domain)
  end
  
  def get_favicon(domain)
    Dir.mkdir(FAVICONS_ROOT) unless File.exists?(FAVICONS_ROOT)
    favicon_location  = File.join(FAVICONS_ROOT, "#{@domain.id}")
    
    begin
      if Net::HTTP.new(@domain.domain).request_head(("favicon.ico")).to_s != "404"      
        Net::HTTP.start(@domain.domain) { |http|
          resp = http.get("/favicon.ico")
          open(favicon_location + ".ico", "w") { |favicon|
            favicon.write(resp.body)
          }
        }
        
        require 'RMagick'
        original_file = Magick::Image.read(favicon_location + ".ico").first.resize_to_fit(16,16)
        # this doesn't work apparently
        # transparent GIFs are given a black background
        # 
        # original_file.background_color = 'none'
        original_file.write(favicon_location + ".gif")

        @domain.update_attribute('favicon', 1)
      end
    rescue
      # it's okay if the favicon can't be obtained
    end
    
    File.delete(favicon_location + ".ico") if File.exists?(favicon_location + ".ico")
  end
  
  def generate_code(length)
    chars = ("a".."z").to_a + ("1".."9").to_a
    code = Array.new(length, '').collect{chars[rand(chars.size)]}.join
    
    # Loop this method if the generated code matches an already existing one
    existing_code = Link.find_by_code(code)
    if existing_code or FORBIDDEN_NAMES.include?(code)
      generate_code(length)
    else
      code
    end
  end
  
end
