require "open3"
require "digest/sha1"

class Webpacker::Compiler
  # Additional paths that test compiler needs to watch
  # Webpacker::Compiler.watched_paths << 'bower_components'
  cattr_accessor(:watched_paths) { [] }

  # Additional environment variables that the compiler is being run with
  # Webpacker::Compiler.env['FRONTEND_API_KEY'] = 'your_secret_key'
  cattr_accessor(:env) { {} }

  delegate :config, :logger, to: :@webpacker

  def initialize(webpacker)
    @webpacker = webpacker
  end

  def compile
    logger.info 'Enter Compiler#compile'
    if stale?
      record_compilation_digest
      run_webpack.tap do |success|
        remove_compilation_digest if !success
      end
    else
      true
    end
  end

  # Returns true if all the compiled packs are up to date with the underlying asset files.
  def fresh?
    logger.info 'Check fresh?'
    if watched_files_digest != last_compilation_digest
      logger.info 'Cache is stale!'
      logger.info "watched_files_digest = #{watched_files_digest}"
      logger.info "last_compilation_digest = #{last_compilation_digest}"
    end
    watched_files_digest == last_compilation_digest
  end

  # Returns true if the compiled packs are out of date with the underlying asset files.
  def stale?
    !fresh?
  end

  private
    def last_compilation_digest
      if compilation_digest_path.exist?
        logger.info "Compilation digest exists!"
      else
        logger.info "Compilation digest DOES NOT EXIST!"
      end

      if config.public_manifest_path.exist?
        logger.info "Public manifest exists at config.public_manifest_path"
      else
        logger.info "Public manifest DOES NOT EXIST at #{config.public_manifest_path}"
      end

      compilation_digest_path.read if compilation_digest_path.exist? && config.public_manifest_path.exist?
    rescue Errno::ENOENT, Errno::ENOTDIR
    end

    def watched_files_digest
      files = Dir[*default_watched_paths, *watched_paths].reject { |f| File.directory?(f) }
      Digest::SHA1.hexdigest(files.map { |f| "#{File.basename(f)}/#{File.mtime(f).utc.to_i}" }.join("/"))
    end

    def record_compilation_digest
      config.cache_path.mkpath
      compilation_digest_path.write(watched_files_digest)
    end

    def remove_compilation_digest
      compilation_digest_path.delete if compilation_digest_path.exist?
    rescue Errno::ENOENT, Errno::ENOTDIR
    end

    def run_webpack
      logger.info "Compiling…"

      # stdout, stderr, status = Open3.capture3(webpack_env, "#{RbConfig.ruby} ./bin/webpack")
      binding.pry
      Open3.popen3(webpack_env, "#{RbConfig.ruby} ./bin/webpack") do |stdout, stderr, status, thread|
        logger.info stdout.read
      end
      # logger.info stdout
      # logger.error stderr

      if status.success?
        logger.info "Compiled all packs in #{config.public_output_path}"
      else
        logger.error "Compilation failed:\n#{stderr}\n#{stdout}"
      end

      status.success?
    end

    def default_watched_paths
      [
        *config.resolved_paths_globbed,
        "#{config.source_path.relative_path_from(Rails.root)}/**/*",
        "yarn.lock", "package.json",
        "config/webpack/**/*"
      ].freeze
    end

    def compilation_digest_path
      @_compilation_digest_path ||= begin
        digest_path = config.cache_path.join(".last-compilation-digest-#{Webpacker.env}")
        logger.info "compilation_digest_path: #{digest_path}"
        digest_path
      end
    end

    def webpack_env
      env.merge("WEBPACKER_ASSET_HOST"        => ActionController::Base.helpers.compute_asset_host,
                "WEBPACKER_RELATIVE_URL_ROOT" => ActionController::Base.relative_url_root)
    end
end
