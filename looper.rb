#coding: utf-8

# ループする
class Looper

  def initialize
    @stop = false
  end


  def start
    if @stop
      return
    end

    proc
    interval = timer_set

    if !interval
      @stop = true
      return
    end

    Reserver.new(interval) { start }
  end

  def stop
    @stop = true
  end

  def stop?
    @stop
  end
end


