# TransitStopMotion.rb
## A video by Matt Grande.

require 'set'
require 'tempfile'
# require 'chunky_png'
require 'oily_png'

class TransitAnimator

	attr_accessor :services
	attr :significant_trips
	attr :max_lat
	attr :min_lat
	attr :max_lng
	attr :min_lng
	attr :img_width
	attr :img_height
	attr :frame_width
	attr :frame_height
	attr :width_offset
	attr :ratio_w
	attr :ratio_h

	attr :min_time
	attr :max_time

	def initialize
		@services = []
		@significant_trips = Set.new
	
		# These values were discovered by looping though stops.txt
		# I've hardcoded them here to eliminate the need for another loop of significant_stop_times.txt
		@max_lat =  43.355081
		@min_lat =  43.156343
		@max_lng = -79.68981
		@min_lng = -80.031414

		# If you're doing this for another city, you'll want to change the frame size to better fit the size of your city.
		# You'll probably also want to add a height_offset, if your city is wider than it is tall.
		#
		# The provided widths/heights are for "HD" size images. I reccomend halving them for a substantial speed 
		# boost while generating the frames of the video.
		@img_width    = 1920 # 960
		@img_height   = 1080 # 540
		@frame_width  = 1054 # 517
		@frame_height = 1080 # 540
		@width_offset = ((img_width - frame_width) / 2).to_i

		@ratio_w = @frame_width / (@max_lng - @min_lng).abs
		@ratio_h = @frame_height / (@max_lat - @min_lat).abs
	end

	def get_significant_trips
		File.open('gtfs/trips.txt').each do |line|
			# We'll save all the trips we care about to 'significant_trips' set.
			@services.each do |s|
				if line.include? s
					parts = line.split(',')
					trip_id = parts[2]	# route_id,service_id,trip_id,trip_headsign,direction_id,block_id,shape_id

					@significant_trips.add trip_id
					next
				end
			end
		end.close
	end

	def get_significant_stop_times
		count = 0
		out_file = File.new('significant_stop_times.txt', 'w')
		begin
			File.open('gtfs/stop_times.txt').each do |line|
				trip_id = line.split(',')[0]
				if significant_trips.include? trip_id
					out_file.write line
					count += 1
				end
			end.close
		ensure
			out_file.close
		end
		return count
	end

	def time_to_frame_converter
		@min_time = 100_000
		@max_time = 0
		t = Tempfile.new('sst')
		begin
			File.open('significant_stop_times.txt', 'r').each do |line|
				parts = line.split(',')
				
				# trip_id,arrival_time,departure_time,stop_id,stop_sequence,stop_headsign,pickup_type,drop_off_type,shape_dist_traveled
				trip_id = parts[0]
				time 	= parts[1]
				stop_id	= parts[3]	
				time_parts = time.split(':').map { |x| x.to_i }
				
				# frame_id = (((hours * 60) + minutes) * 60) + seconds
				# eg, time = 12:04:14
				# frame_id = (((12 * 60) + 4) * 60) + 14
				# 		  => ((720 + 4) * 60) + 14
				# 		  => 43440 + 14
				# 		  => 43454   
				frame_id = (((time_parts[0] * 60) + time_parts[1]) * 60) + time_parts[2]
				
				# frame_id from second to half-minutes:
				# (This reduces the number of frames from 79200 to 2640)
				frame_id = (frame_id / 30).round
				@min_time = frame_id if frame_id < @min_time
				@max_time = frame_id if frame_id > @max_time

				t.puts "#{trip_id},#{frame_id},#{stop_id}"
			end.close

			puts "Lowest frame id: #{min_time}"
			puts "Highest frame id: #{max_time}"

			t.rewind	# Be kind.
			FileUtils.mv(t.path, 'significant_stop_times.txt')
		ensure
			t.close
			t.unlink
		end
	end

	def lat_lng_to_x_y

		# First, let's get all of the GPS Coords of the stops
		t = Tempfile.new('sst2')
		i = 0
		known_stops = {}
		File.open('gtfs/stops.txt', 'r').each do |stop_line|
			# stop_lat,stop_code,stop_lon,stop_id,stop_url,parent_station,stop_desc,stop_name,location_type,zone_id
			stop_parts = stop_line.split(',')
			stop_id = stop_parts[3].strip

			i += 1
			lat = stop_parts[0]
			lng = stop_parts[2]
			known_stops[stop_id] = {:lat => lat, :lng => lng}
		end

		# Now, start counting frame_ids from 0, and convert lat/lng to x/y
		begin
			File.open('significant_stop_times.txt', 'r').each do |sst_line|
				parts = sst_line.split(',')
				# trip_id,frame_id,stop_id
				frame_id = parts[1].to_i
				sst_stop_id = parts[2].strip

				frame_id -= @min_time

				lat = lng = ''

				lat = known_stops[sst_stop_id][:lat].to_f
				lng = known_stops[sst_stop_id][:lng].to_f

				# Now let's convert the GPS co-ords into x,y co-ords.
				x = to_x( lng )
				y = to_y( lat )
					
				t.puts "#{parts[0]},#{frame_id},#{sst_stop_id},#{lat},#{lng},#{x},#{y}"
			end.close

			t.rewind	# Be kind.
			FileUtils.mv(t.path, 'significant_stop_times.txt')
		ensure
			t.close
			t.unlink
		end
	end

	# Draw all the stops on a single image.
	def create_image
		png = ChunkyPNG::Image.new(@img_width, @img_height, ChunkyPNG::Color::BLACK)
		pen = ChunkyPNG::Color.rgb(102, 102, 255)

		prev = nil
		i = 0

		File.open( 'significant_stop_times.txt', 'r' ).each do |line|
			parts = line.split(',')
			# trip_id,frame_id,sst_stop_id,lat,lng,x,y
			trip_id = parts[0]
			x = parts[5].to_i
			y = parts[6].to_i

			if (!prev.nil?) and prev[:trip_id] == trip_id
				i += 1
				puts "#{i} stops drawn" if i % 10_000 == 0

				# Draw a line from the previous stop to this one.
				png.line( 
						prev[:x], prev[:y],
						x, y,
						pen
					)
			end
			
			prev = {:x => x, :y => y, :trip_id => trip_id}
		end

		puts "Saving."
		png.save( 'stops.png' )
	end

	def tween
		prev = nil
		i = 0
		pen = ChunkyPNG::Color.rgb(102, 102, 255)

		File.open( 'significant_stop_times.txt', 'r' ).each do |line|
			parts = line.split(',')
			# trip_id,frame_id,sst_stop_id,lat,lng,x,y
			trip_id = parts[0]
			frame_id = parts[1].to_i
			x = parts[5].to_f
			y = parts[6].to_f

			if (!prev.nil?) and prev[:trip_id] == trip_id
				i += 1
				puts "Stop #{i} (#{Time.now})" if i % 100 == 0
				
				# Draw the stop that we're moving from
				draw_img( prev[:x], prev[:y], prev[:frame_id], pen )

				# Each "frame" represents 30 seconds.
				# Therefore, if there are two minutes between stops, there will be a difference of four frames
				# Stop A: frame_id 4
				# Stop B: frame_id 8
				# This loop moves the 'bus' through frames 5, 6, and 7.
				frame_diff = frame_id - prev[:frame_id]
				if frame_diff > 1
					# Each frame, move the bus this distance.
					x_increment = (x - prev[:x]) / frame_diff
					y_increment = (y - prev[:y]) / frame_diff

					frame_diff -= 1
					(1..frame_diff).each do |inc|
						this_frame_id = prev[:frame_id] + inc
						this_x = (prev[:x] + (x_increment * inc)).round
						this_y = (prev[:y] + (y_increment * inc)).round

						draw_img( this_x, this_y, this_frame_id, pen )
					end
				end

				# Draw the stop that we're moving to
				draw_img( x, y, frame_id, pen )

			end
			
			prev = {:x => x, :y => y, :trip_id => trip_id, :frame_id => frame_id}
		end
		
	end

private
	def to_x(lng)
		l = (lng - @min_lng).abs
		x = (l * @ratio_w).to_i
		return x + @width_offset
	end

	def to_y(lat)
		l = (lat - @max_lat).abs
		y = (l * @ratio_h).to_i
		return y
	end

	# Draw a single dot (read: bus) onto either a new or existing image.
	def draw_img(x, y, i, pen)
		x = x.to_i
		y = y.to_i

		filename = sprintf( "frames/frame-%05d.png", i )
		if File.exists? filename
			png = ChunkyPNG::Image.from_file( filename )
		else
			png = ChunkyPNG::Image.new(@img_width, @img_height, ChunkyPNG::Color::BLACK)
		end

		# Draw each dot as a 3x3 square of pixels
		((x-1)..(x+1)).each do |xi|
			next if xi < 1 || xi >= @img_width

			((y-1)..(y+1)).each do |yi|
				next if yi < 1 || yi >= @img_height

				png[xi, yi] = pen
			end
		end

		png.save( filename, :fast_rgb )
	end

end

animator = TransitAnimator.new

# Let's start with the two Monday-Friday services, as defined by the HSR.
# (See calendar.txt)
# Fuck it, I'm hardcoding them.
animator.services = ['1_merged_878627', '1_merged_878624']

# Now let's get a list of trips for those services.
animator.get_significant_trips

# Should be 6,928 for Hamilton.
puts "#{animator.significant_trips.length} trips found."

# Now we create a new file containing the stop_times of the significant_trips
count = animator.get_significant_stop_times

# Should be 311,099 for Hamilton.
puts "#{count} stop times found"

# Now, open significant_stop_times.txt and convert the times into frame ids
animator.time_to_frame_converter

# No sense in having the frame ID start in the 16,000s, let's reduce to smaller numbers.
# And at the same time, let's get the GPS co-ordinates of each stop.
#
animator.lat_lng_to_x_y

# Sanity check! Let's draw all of the points onto a single image (stops.png)!
animator.create_image

# Draw all the locations between each stop (one frame per half-second)
# WARNING: This literally takes hours to run. Like... 8 - 12 hours.
# That's why it's commented out.
# animator.tween

# Convert the frames into a video via ffmpeg
# puts `ffmpeg -r 27 -i frames/frame-%05d.png -r 30 video_90_90.mpg`

# You're done!
puts Time.now
