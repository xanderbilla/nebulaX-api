#!/bin/bash
# Usage: ./test_video_workflow.sh <API_BASE_URL>
# Example: ./test_video_workflow.sh https://yrm61pl5yg.execute-api.us-east-1.amazonaws.com/dev

set -e
API_BASE_URL="$1"
if [ -z "$API_BASE_URL" ]; then
  echo "Usage: $0 <API_BASE_URL>"
  exit 1
fi

# 1. Fetch all videos and delete them one by one
echo "Fetching all videos..."
VIDEOS=$(curl -s "$API_BASE_URL/api/v1/videos" | jq -r '.data[]?.videoId // empty')
if [ -n "$VIDEOS" ]; then
  for VID in $VIDEOS; do
    echo "Deleting video $VID..."
    curl -s -X DELETE "$API_BASE_URL/api/v1/videos/$VID"
  done
else
  echo "No videos found to delete."
fi

echo "All videos deleted."

# 2. Initiate upload for video, poster, trailer
echo "Initiating upload..."
INIT_RES=$(curl -s -X POST "$API_BASE_URL/api/v1/videos/upload/initiate" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Video",
    "category": "movie",
    "folderPath": "test-movies/automated-test",
    "posterUrl": true,
    "trailerUrl": true,
    "videoUrl": true
  }')

echo "Initiate response: $INIT_RES"

VIDEO_ID=$(echo "$INIT_RES" | jq -r '.data.videoId')
VIDEO_URL=$(echo "$INIT_RES" | jq -r '.data.uploadUrls.video')
POSTER_URL=$(echo "$INIT_RES" | jq -r '.data.uploadUrls.poster')
TRAILER_URL=$(echo "$INIT_RES" | jq -r '.data.uploadUrls.trailer')

echo "Video ID: $VIDEO_ID"
echo "Video URL: $VIDEO_URL"

echo "Uploading video..."
curl -s -X PUT "$VIDEO_URL" --upload-file assets/video.mp4 -H "Content-Type: video/mp4"
echo "Uploading poster..."
curl -s -X PUT "$POSTER_URL" --upload-file assets/poster.jpg -H "Content-Type: image/jpeg"
echo "Uploading trailer..."
curl -s -X PUT "$TRAILER_URL" --upload-file assets/trailer.mp4 -H "Content-Type: video/mp4"

# 3. Complete upload
echo "Completing upload..."
COMPLETE_RES=$(curl -s -X POST "$API_BASE_URL/api/v1/videos/upload/complete" \
  -H "Content-Type: application/json" \
  -d "{
    \"videoId\": \"$VIDEO_ID\",
    \"poster\": true,
    \"trailer\": true,
    \"video\": true
  }")
echo "Upload complete response: $COMPLETE_RES"

# 4. Fetch all videos to verify
echo "Fetching all videos after upload..."
curl -s "$API_BASE_URL/api/v1/videos" | jq

echo "Script complete. Check your AWS console for MediaConvert job status."
