# TransitStopMotion.rb
## A video by Matt Grande.

This ruby script reads GTFS data provided by the City of Hamilton (or any city, really) to create a still image of all the routes and/or a video showing the movement of each vehicle in the fleet.

I created this for fun over the course of a couple evenings. It is not exactly "good" code, but I tried to comment it to explain what was happening. Feel free to ask any questions.

## Requirements

* [chunky\_png](https://github.com/wvanbergen/chunky_png), for generating images. [oily_png](https://github.com/wvanbergen/oily\_png) is highly recommended, as it provides numerous speed enhancements.
* [ffmpeg](http://www.ffmpeg.org/) for the video generation.

## Usage

`ruby ./TransitStopMotion.rb`

* The line `animator.create_image` (line 329 as of this writing) generates a single image of all the routes.
* The line `animator.tween` (line 334 as of this writing) generates all the frames for generating the video. It is commented out by default as running this takes somewhere in the range of 8 to 12 hours.
* The line `ffmpeg -r 27 -i frames/frame-%05d.png -r 30 video_90_90.mpg` (line 337 as of this writing) actually generates the video.

## FAQ

1. **What do the generated video and image look like?**  
[Here is the image](http://i.imgur.com/6KjUkTW.png), and [here is the video](https://vimeo.com/81006232).

1. **I want to generate something like this for my city. How?**  
Locate GTFS data for your city. Replace Hamilton's GTFS data in the `gtfs` folder. Modify the `max/max_lat/lng` and image size properties as necessary. Run the script. Enjoy.

1. **Do you feel bad about including an FAQ section, even though no one has asked any of these questions?**  
Yes.