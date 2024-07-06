mruby-buildconf - ビルド環境検知器
========================================================================

mrbgems の `mrbgem.rake` ファイルでビルド環境を検知するための、ビルド時ライブラリです。
ヘッダファイルやライブラリファイル、マクロなどを検出するための仕組みを備えています。


できること
------------------------------------------------------------------------

  - module `MRuby::Gem::Specification`
      - `gem.configuration_recipe` (refinemented method)


くみこみかた
------------------------------------------------------------------------

 1. `git submodule` でリポジトリに取り込みます。
    ここではサブモジュールパスとして `contrib/mruby-buildconf` を指定していますが、好みのパス名に置き換えることが出来ます。

    ```console
    % git submodule add https://github.com/dearblue/mruby-buildconf.git contrib/mruby-buildconf
    ```

 2. `mrbgem.rake` ファイルの最初の方で内容を読み込みます。
    多少なりとも特殊な読み込み方をしている理由は、mruby-buildconf の複数のリビジョンと混合できるようにすることと、リファインメントを使うためです。

    ```ruby
    internals = File.join(__dir__, "contrib/mruby-buildconf/bootstrap.rb")
    using Module.new { module_eval File.read(internals), internals, 1 }

    MRuby::Gem::Specification.new("mruby-YOUR-GEM") do |s|
      ...
    end
    ```


つかいかた
------------------------------------------------------------------------

 1. `MRuby::Gem::Specification.new` メソッドのブロック引数内で、ライブラリ検出のための設定を `gem.configuration_recipe` メソッドを使って記述します。

    ```ruby
    MRuby::Gem::Specification.new("mruby-YOUR-GEM") do |s|
      ...

      configuration_recipe(
        "windows",              # このラベル名から gem.enable_windows と gem.disable_windows メソッドが定義される
        abort: false,           # `false` であれば、このレシピに失敗してもビルドは続行される
        default: true,          # デフォルトで `gem.enable_windows` を指示される
        libraries: %w(ws2_32),  # このレシピが成功した場合に `linker.libraries` へ追加されるライブラリ
        code: <<~'CODE'         # 検知するための C コード
          #if !defined(_WIN32) && !defined(_WIN64)
          # error "NOT WINDOWS"
          #endif

          int
          main(int argc, char *argv[])
          {
            return 0;
          }
        CODE
      )
    end
    ```

 2. gem の利用者は、gem 設定ブロック内で `gem.enable_windows` や `gem.disable_windows` メソッドを呼ぶことで明示的に有効・無効を指示できます。

    ```ruby
    # in build configuration file

    gem "mruby-YOUR-GEM" do |g|
      g.disable_windows
    end
    ```

    g.enable_windows "*aims"
    g.enable_windows(
      { aim: "name1", include_paths: ..., library_paths: ..., defines: ... },
      { aim: "name2", include_paths: ..., library_paths: ..., defines: ... },
      ...
    )


Specification
------------------------------------------------------------------------

  - Package name: mruby-buildconf
  - Version: 0.1
  - Project status: PROTOTYPE
  - Author: [dearblue](https://github.com/dearblue)
  - Project page: <https://github.com/dearblue/mruby-buildconf>
  - Licensing: [Creative Commons Zero License (CC0 / Public Domain)](LICENSE)
  - Dependency external mrbgems: (NONE)
