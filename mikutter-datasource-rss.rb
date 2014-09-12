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
        entry_title = entry.title.force_encoding("utf-8") 
        description = Sanitize.clean(entry.description)

        msg = Message.new(:message => ("【" + feed_title + "】\n" + entry_title + "\n\n" + description + "\n\n[記事を読む]"), :system => true)

        msg[:rss_feed_url] = entry.url.force_encoding("utf-8")
        msg[:created] = entry.last_updated
        msg[:modified] = Time.now

        # フィードの content と description から URL を抽出
        entry_content = entry.content.force_encoding("utf-8") 
        entry_text = description + entry_content

        # 画像 URL 抽出
        media_url = entry_text.scan(/(<img.*?src=\")(.*?)(\".*?>)/)
        media_url = media_url.collect { |matched|
          matched[1]
        }

        # media 作成
        media = []
        media_url.each_with_index { |url, i|
          media.push({:media_url => url, :indices=>[i,0]})
        }
        media.uniq!

        # Entity 追加
        msg[:entities] = {:urls => [], :media => media}

        # ユーザ
        image_url = if feed.image.empty?
          ICON_COLORS[UserConfig[:datasource_rss_icon]][1]
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
      notice("#{@url} Timer set #{UserConfig[:datasource_rss_period]}")
      UserConfig[:datasource_rss_period]
    end


    def proc
      begin
        notice("#{@url} proc start")

        # パラメータ変更確認
        args = [@url,
                UserConfig[:datasource_rss_loop],
                UserConfig[:datasource_rss_drop_day],
                UserConfig[:datasource_rss_reverse]]

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

            UserConfig[:datasource_rss_load_period] / UserConfig[:datasource_rss_period]
          else
            @load_counter - 1
          end
        end
      rescue => e
        puts e.to_s
        puts e.backtrace
      end
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
      UserConfig[:datasource_rss_period] ||= 1 * 60
      UserConfig[:datasource_rss_load_period] ||= 1 * 60
      UserConfig[:datasource_rss_loop] ||= false
      UserConfig[:datasource_rss_drop_day] ||= 30
      UserConfig[:datasource_rss_reverse] ||= false
      UserConfig[:datasource_rss_icon] ||= 0


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
          multi("Feed URL", :datasource_rss_url)

          select("アイコンの色", :datasource_rss_icon, ICON_COLORS.inject({}){ |result, kv|
            result[kv[0]] = kv[1][0]
            result
          })

          adjustment("RSS取得間隔（秒）", :datasource_rss_load_period, 1, 600)
          adjustment("メッセージ出力間隔（秒）", :datasource_rss_period, 1, 600)
          adjustment("一定期間より前のフィードは流さない（日）", :datasource_rss_drop_day, 1, 365)
          boolean("新しい記事を優先する", :datasource_rss_reverse)
          boolean("ループさせる", :datasource_rss_loop)
        }
    rescue => e
      puts e.to_s
      puts e.backtrace
    end 
  }


  # リンクの処理
  Message::Entity.addlinkrule(:rss, /\[記事を読む\]/) { |segment|
    if segment[:message][:rss_feed_url]
      Gtk::TimeLine.openurl(segment[:message][:rss_feed_url])
    end
  }
}
