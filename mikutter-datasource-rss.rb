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

      UserConfig[:datasource_rss_url].each { |i|
        UserConfig["#{RSS_PERIOD}_#{i}".to_sym] ||= 1 * 60
        UserConfig["#{RSS_LOAD_PERIOD}_#{i}".to_sym] ||= 1 * 60
        UserConfig["#{RSS_IS_LOOP}_#{i}".to_sym] ||= false
        UserConfig["#{RSS_DROP_DAY}_#{i}".to_sym] ||= 30
        UserConfig["#{RSS_REVERSE}_#{i}".to_sym] ||= false
        UserConfig["#{RSS_ICON}_#{i}".to_sym] ||= :black

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
          UserConfig[:datasource_rss_url].each_with_index { |url, i|
            settings(url) {
              adjustment("RSS取得間隔（秒）", get_sym(RSS_LOAD_PERIOD, i), 1, 600)
              adjustment("メッセージ出力間隔（秒）", get_sym(RSS_PERIOD, i), 1, 600)
              adjustment("一定期間より前のフィードは流さない（日）", get_sym(RSS_DROP_DAY, i), 1, 365)
              boolean("新しい記事を優先する", get_sym(RSS_REVERSE, i))
              boolean("ループさせる", get_sym(RSS_IS_LOOP, i))

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

  # リンクの処理
  Message::Entity.addlinkrule(:rss, /\[記事を読む\]/) { |segment|
    if segment[:message][:rss_feed_url]
      Gtk::TimeLine.openurl(segment[:message][:rss_feed_url])
    end
  }
}
