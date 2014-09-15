#coding: utf-8


Plugin.create(:mikutter_datasource_rss) {
  require File.join(File.dirname(__FILE__), "rss_fetcher.rb")
  require File.join(File.dirname(__FILE__), "looper.rb")
  require "rubygems"
  require 'sanitize'


  ICON_COLORS = {
    :red => ["レッド", File.dirname(__FILE__) + "/red-icon-128.png"],
    :blue => ["ブルー", File.dirname(__FILE__) + "/blue-icon-128.png"],
    :black => ["ブラック", File.dirname(__FILE__) + "/black-icon-128.png"],
    :bronze => ["ブロンズ", File.dirname(__FILE__) + "/bronze-icon-128.png"],
    :green => ["グリーン", File.dirname(__FILE__) + "/green-icon-128.png"],
    :lightblue => ["ライトブルー", File.dirname(__FILE__) + "/lightblue-icon-128.png"],
    :mistred => ["ミストレッド", File.dirname(__FILE__) + "/mistred-icon-128.png"],
    :purple => ["パープル", File.dirname(__FILE__) + "/purple-icon-128.png"],
    :mikutter => ["みくったーちゃん", MUI::Skin.get("icon.png")],
  }

  RSS_LOAD_PERIOD = "datasource_rss_load_period"
  RSS_PERIOD = "datasource_rss_period"
  RSS_DROP_DAY = "datasource_rss_drop_day"
  RSS_REVERSE = "datasource_rss_reverse"
  RSS_IS_LOOP = "datasource_rss_loop"
  RSS_ICON = "datasource_rss_icon"
  RSS_SHOW_FEED_TITLE = "datasource_rss_show_feed_title"
  RSS_SHOW_ENTRY_TITLE = "datasource_rss_show_entry_title"
  RSS_SHOW_ENTRY_DESCRIPTION = "datasource_rss_show_entry_description"
  RSS_SHOW_IMAGE, = "datasource_rss_show_image"
  RSS_MAX_IMAGE_NUM = "datasource_rss_max_image_num"

  class FetchLooper < Looper
    def initialize(url)
      super()
      @url = url

      @user = User.new(:id => -3939, :idname => "RSS")
    end


    # フィードをメッセージに変換する
    def create_message(url, feed, entry)
      begin
        feed_title = feed.title.force_encoding("utf-8") 
        description = Sanitize.clean(entry.description)

        # 出力テキスト初期化
        text = ""

        # フィードタイトル表示する？
        if UserConfig["#{RSS_SHOW_FEED_TITLE}_#{@url}".to_sym] then
          text = add_message(text, "【#{feed_title}】")
        end

        # エントリタイトル表示する？
        if UserConfig["#{RSS_SHOW_ENTRY_TITLE}_#{@url}".to_sym] then
          text = add_message(text, entry.title.force_encoding("utf-8"))
        end

        # 内容表示する？
        if UserConfig["#{RSS_SHOW_ENTRY_TITLE}_#{@url}".to_sym] then
          text = add_message(text, description)
        end

        text = add_message(text, "[記事を読む]")

        msg = Message.new(:message => text, :system => true)

        msg[:rss_feed_url] = entry.url.force_encoding("utf-8")
        msg[:created] = entry.last_updated
        msg[:modified] = Time.now

        # フィードの content と description から URL を抽出
        entry_content = entry.content.force_encoding("utf-8") 
        entry_text = description + entry_content

        # media 作成
        if UserConfig["#{RSS_SHOW_IMAGE}_#{@url}".to_sym] then
          media = get_media(entry_text)
        else
          media = []
        end

        # Entity 追加
        msg[:entities] = {:urls => [], :media => media}

        # ユーザ
        image_url = if feed.image.empty?
          ICON_COLORS[UserConfig["#{RSS_ICON}_#{@url}".to_sym]][1]
        else
          feed.image
        end

        @user[:name] = feed_title
        @user[:profile_image_url] = image_url

        msg[:user] = @user

        msg
      rescue => e
        puts e.to_s
        puts e.backtrace
      end
    end


    def timer_set
      rss_period = UserConfig["#{RSS_PERIOD}_#{@url}".to_sym]
      notice("#{@url} Timer set #{rss_period}")
      rss_period
    end


    def proc
      begin
        notice("#{@url} proc start")

        # パラメータ変更確認
        args = [@url,
                UserConfig["#{RSS_IS_LOOP}_#{@url}".to_sym],
                UserConfig["#{RSS_DROP_DAY}_#{@url}".to_sym],
                UserConfig["#{RSS_REVERSE}_#{@url}".to_sym]]

        # パラメータが変わっていた場合、取得オブジェクトを再生成
        if !args[0].empty? && (@prev_args != args)
          notice("#{@url} proc reload")

          @prev_args = args

          @fetcher = RSSFetcher.new(*args, lambda { |*args| create_message(@url, *args) })
          @load_counter = 0
        end

        if @fetcher
          # データ取得
          msg = @fetcher.fetch


          # エントリーあり
          if msg
            notice("#{@url} send to datasource")

            msgs = Messages.new
            msgs << msg

            Plugin.call(:extract_receive_message, "#{@url}".to_sym, msgs)
            Plugin.call(:extract_receive_message, :rss, msgs)
          end

          # RSSロードカウンタ満了
          @load_counter = if @load_counter <= 0
            notice("#{@url} RSS get")

            # RSSを読み込む
            @fetcher.load_rss 

            UserConfig["#{RSS_LOAD_PERIOD}_#{@url}".to_sym] / UserConfig["#{RSS_PERIOD}_#{@url}".to_sym]
          else
            @load_counter - 1
          end
        end
      rescue => e
        puts e.to_s
        puts e.backtrace
      end
    end

    def get_media(media_text)
      # 最大画像数が 0 なら空 media を返却
      max_num = UserConfig["#{RSS_MAX_IMAGE_NUM}_#{@url}".to_sym]
      if max_num == 0 then return [] end

      # media_text から画像 URL 抽出
      media_url = media_text.scan(/(<img.*?src=\")(.*?)(\".*?>)/)
      media_url = media_url.collect { |matched|
        matched[1]
      }

      # media 作成
      media = []
      media_url.each_with_index { |url, i|
        media.push({:media_url => url, :indices=>[i,0]})
      }
      media.uniq!
      media[0..max_num - 1]
    end

    def add_message(src_text, additional_text)
      if src_text == "" then return additional_text end
      return "#{src_text}\n#{additional_text}"
    end
  end


  # データソース登録
  filter_extract_datasources { |datasources|
    begin
      datasources[:rss] = "すべてのRSSフィード"

      UserConfig[:datasource_rss_url].each { |url|
        datasources["#{url}".to_sym] = "RSSフィード : #{url}"
      }

      [datasources]
    rescue => e
      puts e.to_s
      puts e.backtrace
    end
  }


  # 起動時
  on_boot { |service|
    begin
      UserConfig[:datasource_rss_url] ||= []

      init_config

      UserConfig[:datasource_rss_url].each { |i|
        FetchLooper.new(i).start
      }
    rescue => e
      puts e.to_s
      puts e.backtrace
    end
  }


  # 設定
  settings("RSS") {
    begin
        settings("基本設定") {
          multi("Feed URL(追加、削除を行ったら設定画面を開き直してください)", :datasource_rss_url)
        }
        settings("フィード設定") {

          # 設定初期化
          init_config

          UserConfig[:datasource_rss_url].each_with_index { |url, i|

            settings(url) {
              adjustment("RSS取得間隔（秒）", get_sym(RSS_LOAD_PERIOD, i), 1, 600)
              adjustment("メッセージ出力間隔（秒）", get_sym(RSS_PERIOD, i), 1, 600)
              adjustment("一定期間より前のフィードは流さない（日）", get_sym(RSS_DROP_DAY, i), 1, 365)
              boolean("新しい記事を優先する", get_sym(RSS_REVERSE, i))
              boolean("ループさせる", get_sym(RSS_IS_LOOP, i))
              boolean("フィードタイトルを表示", get_sym(RSS_SHOW_FEED_TITLE, i))
              boolean("エントリタイトルを表示", get_sym(RSS_SHOW_ENTRY_TITLE, i))
              boolean("内容を表示", get_sym(RSS_SHOW_ENTRY_DESCRIPTION, i))
              boolean("画像を表示", get_sym(RSS_SHOW_IMAGE, i))
              # 最大値はなんとなく
              adjustment("最大表示画像数", get_sym(RSS_MAX_IMAGE_NUM, i), 1, 256)

              select("アイコンの色", get_sym(RSS_ICON, i), ICON_COLORS.inject({}){ |result, kv|
                result[kv[0]] = kv[1][0]
                result
              })
            }
          }
        }
    rescue => e
      puts e.to_s
      puts e.backtrace
    end 
  }

  def get_sym(setting, index)
    return "#{setting}_#{UserConfig[:datasource_rss_url][index]}".to_sym
  end

  def init_config()
    UserConfig[:datasource_rss_url].each_with_index { |url, i|
      # 設定初期化
      UserConfig["#{RSS_PERIOD}_#{url}".to_sym] ||= 1 * 60
      UserConfig["#{RSS_LOAD_PERIOD}_#{url}".to_sym] ||= 1 * 60
      UserConfig["#{RSS_IS_LOOP}_#{url}".to_sym] ||= false
      UserConfig["#{RSS_DROP_DAY}_#{url}".to_sym] ||= 30
      UserConfig["#{RSS_REVERSE}_#{url}".to_sym] ||= false
      UserConfig["#{RSS_ICON}_#{url}".to_sym] ||= :black

      # テキストについて
      init_bool(UserConfig["#{RSS_SHOW_FEED_TITLE}_#{url}".to_sym], true)
      init_bool(UserConfig["#{RSS_SHOW_ENTRY_TITLE}_#{url}".to_sym], true)
      init_bool(UserConfig["#{RSS_SHOW_ENTRY_DESCRIPTION}_#{url}".to_sym], true)

      # 画像について
      init_bool(UserConfig["#{RSS_SHOW_IMAGE}_#{url}".to_sym], true)
      UserConfig["#{RSS_MAX_IMAGE_NUM}_#{url}".to_sym] ||= 256

    }
  end

  def init_bool(config, default)
    if config == nil then
      config = default
    end
  end

  # リンクの処理
  Message::Entity.addlinkrule(:rss, /\[記事を読む\]/) { |segment|
    if segment[:message][:rss_feed_url]
      Gtk::TimeLine.openurl(segment[:message][:rss_feed_url])
    end
  }
}
