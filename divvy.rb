require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require_relative 'secrets.rb'

Capybara.default_driver    = :poltergeist
Capybara.javascript_driver = :poltergeist
Capybara.run_server        = false
Capybara.app_host          = 'https://member.divvybikes.com'

Trip = Struct.new(:id, :start_station, :start_time, :end_station, :end_time, :duration) do
  def to_s
    "(#{id}) #{start_station}@#{start_time_str}-#{end_station}@#{end_time_str}#{duration_str}"
  end

  def duration_str
    duration.empty? ? '' : " (#{duration})"
  end

  def start_time_str
    simplify_time(start_time)
  end

  def end_time_str
    in_progress? ? end_time : simplify_time(end_time)
  end

  private

  def in_progress?
    duration.empty? && end_station == 'Trip Open' && end_time == 'Trip Open'
  end

  def simplify_time(time) # '06/01/2017 12:09 PM' -> '12:09pm'
    time[-8..-4] + time[-2..-1].downcase
  end
end

NoTrip = Struct.new(:message) do
  def to_s
    'None found for this month'
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

scraper = TripScraper.new
loop do
  puts "[#{Time.now.to_i}] Scraping page..."

  trip = scraper.get_last_trip
  puts "[#{Time.now.to_i}] #{trip.to_s}"

  sleep 60
end
