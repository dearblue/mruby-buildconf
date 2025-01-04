=begin
## 全体専用オプション
  abort: true,      ## このレシピに失敗したらビルドを失敗させる。
  abort: false,     ## このレシピに失敗してもビルドは失敗しないが、機能が制限される。既定値。
  default: true,    ## 検知を初期状態で有効にする。既定値。
  default: false,   ## 検知を初期状態で無効にする。`abort: true` とは仲が悪い。
  all: true,        ## レシピのすべてを必要とする。
  all: false,       ## レシピのいずれかを必要とする。既定値。

## 個別オプション

  srcs: [],         ## コンパイルが必要なソースコード。ファイルパスではなくハッシュの形でソースコードをコンパイルするための手順を記述できる？？？
  objs: [],         ## アーカイブ時に追加されるオブジェクトファイル。
  linking: true,    ## false でコンパイルのみ？
  code: "c code",   ## リンク確認するためのソースコード。
  code: { code: "code", type: ".c" },
  variation: nil,   ## 個別に対する名前。`all: false` の場合は `enable_***` でこれだけを有効化出来る。
  standard: true,   ## 標準で有効化される。既定値。
  standard: false,  ## 標準で無効のため、variation で指定する必要がある。

## 個別排他的オプション

  # pkgconf を使ったビルドスイッチの取得
  pkgconf: { file: "$pkgdir/lib/pkgconfig/libbzip3.pc", env: {}, var: { pkgdir: "/usr/local" } },

  # sh configure && make によるライブラリのビルド
  configure: { file: "contrib/bzip3/c/configure", args: [], env: { MAKE: "make" }, var: {}, dir: "work directory" },

  # automake && sh configure && make によるライブラリのビルド
  automake: { file: "contrib/bzip3/c/Makefile.am", args: [], env: { MAKE: "make" }, dir: "work directory" },

  # cmake && make によるライブラリのビルド (make が使われるか nmake が使われるかは、呼び出し元の make により決定される？)
  cmake: { file: "contrib/bzip3/c/CMakeList.txt", args: [], env: { MAKE: "make" }, dir: "work directory" },

  # make によるライブラリのビルド
  make: { file: "contrib/bzip3/c/Makefile", args: [], env: { MAKE: "make" }, dir: "work directory" },

  # 埋め込みシェルスクリプトを実行してライブラリのビルドを行う
  sh: { command: "script", args: [], env: {}, dir: "work directory" },

  # 外部シェルスクリプトを実行してライブラリのビルドを行う
  sh: { file: "script file", args: [], env: {}, dir: "work directory" },
=end

require "mruby/source"
require "json"
require "tmpdir"

MRuby::Build::CHDIR_MUTEX ||= Mutex.new

using Module.new {
  refine Object do
    def TODO(mesg)
      warn <<~WARN
      ######## \e[7mTODO\e[m: #{caller(1)[0]} ########
      #{"#{mesg}".gsub(/^(?!\s*$)/, "  | ")}

      WARN
    end

    def unless_empty?
      return nil if empty?
      return yield self if block_given?
      self
    end
  end

  refine NilClass do
    def empty?
      true
    end
  end

  refine Hash do
    def dive_to(key)
      ref = self[key] or raise "[BUG] need `#{key}` key [BUG]"

      case
      when ref.kind_of?(String)
        yield({ file: ref })
      when ref[:dir].empty?
        yield ref
      else
        MRuby::Build::CHDIR_MUTEX.lock {
          Dir.chdir(ref[:dir]) { yield ref }
        }
      end
    end

    def lookup_tasting(trace: caller)
      opts = self.keys - COMMON_OPTIONS
      case
      when opts.size == 0
        return BUILD_TASTING[:compile]
      when opts.size == 1 && EXCLUSIVE_OPTIONS.include?(*opts)
        return BUILD_TASTING[opts[0]]
      else
        raise ArgumentError, "unknown or exclusive keywords (#{opts.sort.join(", ")})", trace
      end
    end
  end

  refine String do
    def file_newer_than(*paths)
      File.file?(self) && File.mtime(self) > paths.map { |e| File.mtime(e) }.max
    end
  end

  refine NilClass do
    def each_with_object(aggregator)
      aggregator
    end
  end

  refine String do
    def each_with_object(aggregator)
      yield(self, aggregator)
      aggregator
    end
  end

  refine Hash do
    def ensure_configuration_element
      raise ArgumentError, "nothing for variation" unless self[:variation]

      self
    end
  end

  refine String do
    def ensure_configuration_element
      { variation: self }
    end
  end

  refine String do
    def generate_code
      [self, ".c"]
    end
  end

  refine Hash do
    def generate_code
      if has_key?(:code)
        [self[:code], self[:type] || ".c"]
      else
        case self[:type] || ".c"
        when ".c"
          [<<~CODE, ".c"]
            #include <stdio.h>
            #{self[:header_files].each_with_object("") { |e, a| a << %(#include <#{e}>\n) }}

            int
            main(int argc, char *argv[])
            {
            #{self[:functions].each_with_object("") { |e, a| a << %(  { const void *func = (const void *)#{e}; printf("%p\\n", func); }\n) }}
              return 0;
            }
          CODE
        when ".cc", ".cxx", ".cpp"
          [<<~CODE, ".cxx"]
            #include <stdio.h>
            #{self[:header_files].each_with_object("") { |e, a| a << %(#include <#{e}>\n) }}

            int
            main(int argc, char *argv[])
            {
            #{self[:functions].each_with_object("") { |e, a| a << %(  { const void *func = (const void *)#{e}; printf("%p\\n", func); }\n) }}
              return 0;
            }
          CODE
        else
          0/0
        end
      end
    end
  end
}

refine String do
  def dir_glob(*pat, **opts, &block)
    base = self.gsub(/[\[\]\{\}]/) { |e| "\\#{e}" }
    pat.map! { |e| File.join base, e }
    Dir.glob(*pat, **opts, &block)
  end
end

refine MRuby::Gem::Specification.singleton_class do
  def new(*args, **opts, &block)
    super do |spec|
      @configurations__VT0JX8AEMY__ = {}
      @last_initializer__VT0JX8AEMY__ = nil

      @build_config_initializer__origin__ = @build_config_initializer
      @build_config_initializer = ->(_spec) {
        instance_eval(&@build_config_initializer__origin__) if @build_config_initializer__origin__
        instance_eval(&@last_initializer__VT0JX8AEMY__) if @last_initializer__VT0JX8AEMY__

        configcache = File.join(self.build_dir, "configure.cache")

        file File.join(build_dir, "gem_init.c") => configcache
        dir.dir_glob("src/**/*") { |src| file src => configcache if File.file?(src) }
        #MRUBY_ROOT.dir_glob("src/**/*") { |src| file src => configcache if File.file?(src) }
        # ↑ mruby core を含めたすべてのファイルが再コンパイルすることになるので別の手段を考える

        task "configure" => configcache

        task configcache do |task|
          if configcache.file_newer_than(MRUBY_CONFIG, File.join(spec.dir, "mrbgem.rake"), __FILE__)
            timestamp = Time.at(1)
            conf = JSON.load_file(configcache)
          else
            timestamp = Time.now
            conf = configuration(configcache)
          end

          task.define_singleton_method(:timestamp, &-> { timestamp })

          conf["defines"].unless_empty? { |me| cc.defines << me }
          conf["cflags"].unless_empty? { |me| cc.flags << me }
          conf["include_paths"].unless_empty? { |me| cc.include_paths << me }
          conf["ldflags"].unless_empty? { |me| linker.flags_before_libraries << me }
          conf["library_paths"].unless_empty? { |me| linker.library_paths << me }
          conf["libraries"].unless_empty? { |me| linker.libraries << me }
          conf["objs"].unless_empty? { |me|
            me = me.flatten
            spec.objs.concat me
            file spec.build.libmruby_static => me
          }
          conf["srcs"].unless_empty? { |me|
            me = me.flatten.map { |f| objfile f.relative_path_from(dir).pathmap("#{build_dir}/%X") }
            spec.objs.concat me
            file spec.build.libmruby_static => me
          }
        end
      }

      instance_eval(&block)
    end
  end
end

# これらはリンクまで成功した場合は真を返す。どこかで失敗した場合は偽を返す。
BUILD_TASTING = {
  compile: ->(env, recipe, defines: nil, cflags: nil, include_paths: nil, ldflags: nil, library_paths: nil, libraries: nil) {
    unless code = recipe[:code]
      env.defines       << defines        unless defines.empty?
      env.cflags        << cflags         unless cflags.empty?
      env.include_paths << include_paths  unless include_paths.empty?
      env.ldflags       << ldflags        unless ldflags.empty?
      env.library_paths << library_paths  unless library_paths.empty?
      env.libraries     << libraries      unless libraries.empty?
      %i(defines cflags include_paths ldflags library_paths libraries objs srcs).each { |e|
        env.__send__(e) << recipe[e]      unless recipe[e].empty?
      }
      return true
    end

    (code, type) = code.generate_code
    env.try_link code,
                 type: type,
                 defines: [*recipe[:defines], *defines],
                 cflags: [*recipe[:cflags], *cflags],
                 include_paths: [*recipe[:include_paths], *include_paths],
                 ldflags: [*recipe[:ldflags], *ldflags],
                 library_paths: [*recipe[:library_paths], *library_paths],
                 libraries: [*recipe[:libraries], *libraries]
  },
  pkgconf: ->(env, recipe, cflags: nil, ldflags: nil, **opts) {
    # pkgconf  =>  cc
    cflags1 = ldflags1 = nil
    recipe.dive_to(:pkgconf) { |ref|
      pkgconf = ref.dig(:env, "PKGCONF") || env["PKGCONF"] || "pkgconf"
      [*ref.dig(:paths), nil].product([*ref.dig(:file)]) { |dir, pcfile|
        file = dir ? File.join(dir, pcfile) : pcfile
        cflags1 = env.run_sub((ref[:env] || {}), pkgconf, file, "--cflags")
        ldflags1 = env.run_sub((ref[:env] || {}), pkgconf, file, "--libs")
        break if cflags1 && ldflags1
        cflags1 = ldflags1 = nil
      }
    }

    return false unless cflags1 && ldflags1
    return true unless recipe[:code]

    BUILD_TASTING[:compile].call(env, recipe, cflags: [*cflags, *cflags1], ldflags: [*ldflags, *ldflags1], **opts)
  },
  configure: ->(env, recipe, **opts) {
    # sh configure  =>  make  =>  cc
    recipe.dive_to(:configure) { |ref|
      sh = ref.dig(:env, "SH") || env["SH"] || "sh"
      make = ref.dig(:env, "MAKE") || env["MAKE"] || "make"
      TODO "ref[:var] で env, file, args を展開する"
      env.run (ref[:env] || {}), sh, ref[:file], *ref[:args] or return false
      env.run (ref[:env] || {}), make, *ref.dig(:make, :args) or return false
    }

    return true unless recipe[:code]

    BUILD_TASTING[:compile].call(env, recipe, **opts)
  },
  automake: ->(env, recipe, **opts) {
    # automake  =>  sh configure  =>  make  =>  cc
    0/0
  },
  cmake: ->(env, recipe, **opts) {
    # cmake  =>  make  =>  cc
    0/0
  },
  make: ->(env, recipe, **opts) {
    # make  =>  cc
    0/0
  },
  sh: ->(env, recipe, **opts) {
    # sh script  =>  cc
    recipe.dive_to(:sh) { |ref|
      sh = ref.dig(:env, "SH") || env["SH"] || "sh"
      if ref.has_key? :file
        env.run (ref[:env] || {}), sh, ref[:file], *ref[:args] or return false
      else
        env.run (ref[:env] || {}), sh, "-c", ref[:command], *ref[:args] or return false
      end
    }

    return true unless recipe[:code]

    BUILD_TASTING[:compile].call(env, recipe, **opts)
  },
  vcpkg: ->(env, recipe, **opts) {
    # vcpkg  =>  ???  =>  cc
    # https://github.com/microsoft/vcpkg
    0/0
  }
}

COMMON_OPTIONS = %i(variation code abi standard defines include_paths cflags libraries ldflags library_paths objs srcs prepare fetch patch)
EXCLUSIVE_OPTIONS = BUILD_TASTING.keys

refine MRuby::Gem::Specification do
  def last_initializer__VT0JX8AEMY__(&block)
    @last_initializer__VT0JX8AEMY__ = block
  end

  #
  # call-seq:
  #   configuration_recipe(label, *recipe, abort: false, default: true, all: false, **opts)
  #
  def configuration_recipe(label, *recipe, abort: false, default: true, all: false, **opts)
    recipe << opts unless opts.empty?

    recipe.each { |r| r.lookup_tasting }

    label2 = label.gsub(/[^0-9A-Za-z_]+/m, "_")
    @configuration_elements ||= {}
    @configuration_elements[label2] = (default ? {} : nil)

    if abort
      raise ArgumentError, "`default` cannot be false if `abort` is true" unless default
    else
      define_singleton_method :"disable_#{label2}", -> { @configuration_elements[label2] = nil }
      define_singleton_method :"#{label2}_enabled?", -> { !!@configuration_elements[label2] }
      define_singleton_method :"#{label2}_disabled?", -> { !@configuration_elements[label2] }
    end

    raise NotImplementedError if all

    unless all
      define_singleton_method :"enable_#{label2}", ->(*opts) {
        opts.map! { |o| o.ensure_configuration_element }
        @configuration_elements[label2] = opts
      }
    end

    @configurations__VT0JX8AEMY__[label] = [recipe, abort, caller, label2]

    self
  end

  # Makefile や CMakeList.txt などのための準備を行う。
  # レシピに含まれる遅延評価のためのブロックを静的な値 (文字列) に置き換える。
  def prepare_makefile
    0/0
  end

  def configuration(configcache)
    _pp "CONFIG ", configcache.relative_path

    envs = @configurations__VT0JX8AEMY__.each_pair.map { |label, (recipe, abort, trace, label2)|
      ce = @configuration_elements[label2]
      next nil unless ce

      env = Object.new
      if build.kind_of? MRuby::CrossBuild
        env.define_singleton_method :[], ->(var) { nil }
      else
        env.define_singleton_method :[], ->(var) { ENV[var] }
      end

      gem = self

      env.singleton_class.class_eval do
        %i(defines cflags include_paths ldflags library_paths libraries objs srcs).each { |e|
          cube = []
          define_method e, -> { cube }
        }
      end

      tools = self.build.class::COMMANDS.map do |name|
        tool = self.instance_variable_get("@#{name}")&.dup or next
        tool.singleton_class.class_eval do
          def try(*args, **opts, &block)
            run *args, **opts, &block rescue nil
          end

          define_method :sh, ->(*args, **opts, &block) {
            env.sh *args, in: File::NULL or fail
          }

          def _pp(*args)
          end
        end

        env.define_singleton_method name, -> { tool }
        tool
      end

      env.linker.flags << self.build.linker.flags
      env.linker.library_paths << self.build.linker.library_paths
      env.linker.libraries << self.build.linker.libraries

      env.define_singleton_method :try_link, ->(code, type: ".c", defines: [], cflags: [], include_paths: [], ldflags: [], library_paths: [], libraries: []) {
        Dir.mktmpdir do |dir|
          cc = tools.find { |e| e.source_exts.include? type }
          src = File.join(dir, %(code#{type}))
          obj = gem.build.objfile(File.join(dir, "code"))
          exe = gem.build.exefile(File.join(dir, "code"))
          File.write src, code

          if cc.try(obj, src, defines, include_paths, cflags) && env.linker.try(exe, [obj], libraries, library_paths, [], ldflags)
            env.defines       << defines        if defines       && !defines.empty?
            env.cflags        << cflags         if cflags        && !cflags.empty?
            env.include_paths << include_paths  if include_paths && !include_paths.empty?
            env.ldflags       << ldflags        if ldflags       && !ldflags.empty?
            env.library_paths << library_paths  if library_paths && !library_paths.empty?
            env.libraries     << libraries      if libraries     && !libraries.empty?
            true
          else
            false
          end
        end
      }

      command_message = ""
      env.define_singleton_method :command_message, -> { command_message }

      env.define_singleton_method :sh, ->(*args, **opts) {
        IO.popen(*args, mode: "r", err: [:child, :out], **opts) { |pipe| command_message << pipe.read }
        Process.last_status.success?
      }

      env.define_singleton_method :run, ->(*args, **opts) {
        evar = args.shift if args.size > 0
        IO.popen(evar, args, mode: "r", err: [:child, :out], **opts) { |pipe| command_message << pipe.read }
        Process.last_status.success?
      }

      # command substitution
      env.define_singleton_method :run_sub, ->(*args, mode: "r", **opts) {
        evar = args.shift if args.size > 0
        ret = nil
        status = nil
        IO.pipe do |r, w|
          th = Thread.new { command_message << r.read }
          ret = IO.popen(evar, args, mode: mode, err: w, **opts) { |pipe| pipe.read }
          status = Process.last_status.success?
        ensure
          w.close rescue nil
          th.join rescue nil if th
        end

        status ? ret.chomp : nil
      }

      if ce.empty?
        ce = nil
      else
        ce = ce.each_with_object({}) { |e, a| a[e[:variation]] = e }
      end

      failall = recipe.none? { |r|
        tasting = r.lookup_tasting(trace: trace)

        # TODO: `all: true` の場合はすべてを検証する必要があるため、オーバーライドしない構成も検証する必要がある (この辺の仕様はどうする？)
        if ce
          next false unless e = ce[r[:variation]]
          e = e.dup
          e.delete(:variation)
        else
          next false unless r.fetch(:standard, true)
          e = {}
        end

        tasting.call(env, r, **e)
      }
      if failall && abort
        fail RuntimeError, <<~ERR, trace
          failed to configure required for #{label} in #{self.name}
          You may need to call `gem.enable_#{label}` in the build configuration file and give it arguments to adjust.
          - - -
          #{command_message}
          - - -
        ERR
      end

      #$stderr.puts command_message.gsub(/^(?!\s*$)/, "\t")

      env
    }

    envs.compact!

    config = {
      "defines" =>          envs.map { |e| e.defines },
      "cflags" =>           envs.map { |e| e.cflags },
      "include_paths" =>    envs.map { |e| e.include_paths },
      "ldflags" =>          envs.map { |e| e.ldflags },
      "library_paths" =>    envs.map { |e| e.library_paths },
      "libraries" =>        envs.map { |e| e.libraries },
      "objs" =>             envs.map { |e| e.objs },
      "srcs" =>             envs.map { |e| e.srcs },
    }.transform_values { |values|
      values.flatten!
      values.compact!
      values
    }.delete_if { |k, v| v.empty? }

    maps = config.map { |(name, values)|
      values = values.flatten.compact
      next nil if values.empty?

      %(  #{name.inspect}: [\n#{values.map { |e| %(    #{e.inspect}) }.join(",\n")}\n  ])
    }.compact.join(",\n")

    mkdir_p File.dirname configcache
    File.write configcache, <<~"CONFIG.CACHE"
      {
      #{maps}
      }
    CONFIG.CACHE

    config
  end
end

unless Rake::Task.tasks.find { |e| e.name == "configure" }
  Rake.application.last_description = "configure dependent libraries"
  Rake::Task.define_task "configure"
end

=begin
TODO:
  - Rust のような未知のコンパイラ設定にはどう対応する？
  - automake や cmake のための出力にはどう対応する？
  - configure (autoconf) や cmake+msvc でライブラリをビルドする場合の流れはどんな感じになる？
  - #have_flags や #have_library のようなメソッドも追加したい
  - グローバル変数を使いまくる mkmf との互換性は無理
  - env.command_message にコマンドの渡し方やコンパイルを試す時のコードを出力する
  - リンクを行わない選択肢を用意する (コンパイルのみという意味)

GUIDELINES:
  - make や cmake を出力することを考慮して、静的な記述で実現できるようにする。
=end
