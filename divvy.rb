require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'date'
require 'twilio-ruby'
require_relative 'secrets.rb'

Capybara.default_driver    = :poltergeist
Capybara.javascript_driver = :poltergeist
Capybara.run_server        = false
Capybara.app_host          = 'https://member.divvybikes.com'

Trip = Struct.new(:id, :start_station, :start_time, :end_station, :end_time, :duration) do
  def to_s
    "(#{id}) #{start_station}@#{start_time_str}-#{end_station}@#{end_time_str}#{duration_str}"
  end

  def started_summary
    "Trip started #{start_time_str} at #{start_station}"
  end

  def ended_summary
    "Trip ended #{end_time_str} at #{end_station} (#{duration})"
  end

  def running_out_of_time_summary
    "Trip started #{start_time_str} has about five minutes left"
  end

  def running_out_of_time?
    return false unless in_progress?

    seconds_in_progress = Time.now - Time.parse(start_time)
    seconds_in_progress > 24*60
    #seconds_in_progress > 3*60 # TODO
  end

  def in_progress?
    duration.empty? && end_station == 'Trip Open' && end_time == 'Trip Open'
  end

  private

  def duration_str
    duration.empty? ? '' : " (#{duration})"
  end

  def start_time_str
    simplify_time(start_time)
  end

  def end_time_str
    in_progress? ? end_time : simplify_time(end_time)
  end

  def simplify_time(time) # '06/01/2017 12:09 PM' -> '12:09pm'
    time[-8..-4] + time[-2..-1].downcase
  end
end

NoTrip = Struct.new(:message) do
  def to_s
    'None found for this month'
  end

  def id
    nil
  end

  def in_progress?
    false
  end
end

class SMS
  def initialize
    @client = Twilio::REST::Client.new(Secrets::TWILIO_SID, Secrets::TWILIO_AUTHTOKEN)
  end

  def send(text)
    @client.account.messages.create({
      :from => Secrets::TWILIO_FROM,
      :to => Secrets::TWILIO_TO,
      :body => text
    })
  end
end

class TripScraper
  include Capybara::DSL

  def get_last_trip
    page.driver.browser.js_errors = false

    # login
    visit '/login'
    fill_in 'Username', with: Secrets::DIVVY_USERNAME
    fill_in 'Password', with: Secrets::DIVVY_PASSWORD
    click_button 'Login'
    sleep(1.0)

    # go to trips
    click_link('Trips')
    sleep(1.0)

    # get last trip or message saying there are none
    tds = page.all('#tripTable tbody tr').last.all('td')
    if tds.count == 1
      NoTrip.new(tds.first.text)
    else
      Trip.new(*tds.map { |td| td.text })
    end
  end
end

sender    = SMS.new
scraper   = TripScraper.new
last_trip = NoTrip.new('init')
alerted   = false
loop do
  trip = scraper.get_last_trip
  puts "[#{Time.now.to_i}] #{trip.to_s}"

  # same trip but status changed - that should mean the trip ended
  if last_trip.id == trip.id && last_trip.in_progress? != trip.in_progress?
    sender.send(trip.ended_summary)
  end

  # new trip id and the current trip is in progress - just started
  if last_trip.id != trip.id && trip.in_progress?
    sender.send(trip.started_summary)
  end

  if trip.running_out_of_time?
    sender.send("#{trip.running_out_of_time_summary}") unless alerted
    alerted = true
  else
    alerted = false
  end

  last_trip = trip
  sleep (last_trip.in_progress? ? 10 : 60)
end
