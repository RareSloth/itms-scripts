#!/usr/bin/env ruby

require 'set'
require 'JSON'
require_relative 'itms_utils.rb'
require_relative 'itms_app_store.rb'
require_relative 'itms_iap.rb'
require_relative 'itms_achievements.rb'
require_relative 'itms_leaderboards.rb'

config_filename = 'itms.config'

if ARGV.include? '-c'
  config_filename_index = ARGV.index('-c') + 1
  config_filename = ARGV[config_filename_index]
end

skip_download = ARGV.include? '--skip-download'
only_download = ARGV.include? '--only-download'

unless File.exists? config_filename
  puts "[ITMS] Could not find config filename #{config_filename}"
  exit 1
end

config = JSON.parse(File.read(config_filename))
username = config['username']
username = ENV['ITMS_USERNAME'] if username.nil?
password = config['password']
password = ENV['ITMS_PASSWORD'] if password.nil?
app_id = config['app_id']
version = config['version']

destination = '.'
itms_package_name = "#{app_id}.itmsp"

log_name = 'itms.log'

if File.exists? log_name
  File.truncate(log_name, 0)
end

unless skip_download
  puts "[ITMS] Downloading itms package #{app_id}"
  # Download the itms package to get a stub
  unless ITMSUtils.download_metadata(username, password, app_id, destination, log_name)
    puts "[ITMS] [ERROR] Failed to download itms package #{app_id}, check #{log_name} for more info"
    exit 2
  end
  if only_download
    puts "[ITMS] Completed download"
    exit 0
  end
end

unless File.exists? File.expand_path(itms_package_name)
  puts "[ITMS] Missing itms package for #{app_id}"
  exit 3
end

if config['generate_app_store_xml']
# Generate the app store xml and copy the images needed for upload
  puts "[ITMS] Generating App Store xml..."
  base_image_names = config['app_store_image_base_names']
  if !config['upload_app_store_screenshots']
    base_image_names = nil
  end
  app_store_xml, images_used = ITMSAppStore.app_store_xml(version, 'app_store/app_store_locales.tsv', 'app_store', base_image_names)
  ITMSUtils.copy_images(images_used, itms_package_name)
end

if config['generate_iap_xml']
# Generate the iap xml and copy the images needed for upload
  puts "[ITMS] Generating In App Purchases xml..."
  iap_xml, images_used = ITMSIAP.iap_xml('iap/iap_metadata.csv', 'iap/iap_locales.csv', 'iap')
  ITMSUtils.copy_images(images_used, itms_package_name)
end

if config['generate_achievements_xml']
# Generate the achievements xml and copy the images needed for upload
  puts "[ITMS] Generating Achievements xml..."
  achievements_xml, images_used = ITMSAchievements.achievements_xml('achievements/achievements_metadata.csv', 'achievements/achievements_locales.csv', 'achievements')
  ITMSUtils.copy_images(images_used, itms_package_name)
end

if config['generate_leaderboards_xml']
# Generate the leaderboards xml and copy the images needed for upload
  puts "[ITMS] Generating Leaderboards xml..."
  leaderboards_xml, images_used = ITMSLeaderboards.leaderboards_xml('leaderboards/leaderboards_metadata.csv', 'leaderboards/leaderboards_locales.csv', 'leaderboards')
  ITMSUtils.copy_images(images_used, itms_package_name)
end

# Replace the stubbed xml we downloaded with
puts "[ITMS] Replacing itms package metadata with generated xml..."
metadata_filename = "#{itms_package_name}/metadata.xml"
ITMSUtils.replace_xml(metadata_filename, version, app_store_xml, iap_xml, achievements_xml, leaderboards_xml)

package_filepath = "#{destination}/#{itms_package_name}"
# dry_run will trigger a verify with the package instead of an upload
dry_run = config['dry_run']
method = dry_run ? 'verify' : 'upload'
puts "[ITMS] #{method} itms package #{app_id}"
unless ITMSUtils.upload_metadata(username, password, package_filepath, log_name, dry_run)
  puts "[ITMS] [ERROR] Failed to #{method} metadata for itms package #{app_id}, check #{log_name} for more info"
  exit 4
end

# Clean if needed
if config['clean_after_submit']
  puts "[ITMS] Cleaning up itms package"
  `rm -rf #{itms_package_name}`
end

puts "[ITMS] Complete!"
