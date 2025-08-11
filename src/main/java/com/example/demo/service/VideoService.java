package com.example.demo.service;

import com.example.demo.dto.request.UpdateVideoRequest;
import com.example.demo.dto.request.InitiateUploadRequest;
import com.example.demo.dto.request.InitiateFileUpdateRequest;
import com.example.demo.dto.request.CompleteUploadRequest;
import com.example.demo.dto.request.CompleteFileUpdateRequest;
import com.example.demo.dto.response.InitiateUploadResponse;
import com.example.demo.dto.response.VideoDetailResponse;
import com.example.demo.exception.S3OperationException;
import com.example.demo.exception.VideoNotFoundException;
import com.example.demo.exception.VideoProcessingException;
import com.example.demo.model.Video;
import com.example.demo.repository.VideoRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.ScanRequest;
import software.amazon.awssdk.services.dynamodb.model.ScanResponse;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Core business service for video management operations in Nebulax system.
 * Handles video upload workflows, metadata management, S3 presigned URL generation,
 * and complete CRUD operations for video entities with DynamoDB persistence.
 * 
 * @author Vikas Singh
 * @since August 3, 2025
 * @see com.example.demo.model.Video
 * @see com.example.demo.repository.VideoRepository
 * @see com.example.demo.controller.VideoController
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VideoService {

    private final VideoRepository videoRepository;
    private final S3Client s3Client;
    private final S3Presigner s3Presigner;
    private final DynamoDbClient dynamoDbClient;

    @Value("${app.cloudfront.base-url:https://d1234567890.cloudfront.net}")
    private String cloudfrontBaseUrl;

    @Value("${app.dynamodb.videos-table:Videos}")
    private String videosTableName;

    @Value("${app.s3.bucket:}")
    private String videosBucketName;

    @Value("${app.s3.transcoded.bucket:}")
    private String transcodedBucketName;

    public List<Video> getAllVideos() {
        log.info("Fetching all videos from DynamoDB");

        try {
            ScanRequest scanRequest = ScanRequest.builder()
                    .tableName(videosTableName)
                    .build();

            ScanResponse scanResponse = dynamoDbClient.scan(scanRequest);

            // Convert DynamoDB items to Video objects using the repository's table schema
            return scanResponse.items().stream()
                    .map(item -> {
                        Video video = new Video();
                        video.setVideoId(item.get("videoId").s());
                        video.setTitle(item.get("title") != null ? item.get("title").s() : "");
                        video.setType(item.get("type") != null ? item.get("type").s() : "video");
                        video.setCategory(item.get("category") != null ? item.get("category").s() : "");
                        video.setFolderPath(item.get("folderPath") != null ? item.get("folderPath").s() : "");
                        video.setVideoUrl(item.get("videoUrl") != null ? item.get("videoUrl").s() : "");
                        video.setCreatedAt(item.get("createdAt") != null ? item.get("createdAt").s() : "");
                        video.setModifiedAt(item.get("modifiedAt") != null ? item.get("modifiedAt").s() : "");
                        video.setS3Key(item.get("s3Key") != null ? item.get("s3Key").s() : "");
                        video.setPosterUrl(item.get("posterUrl") != null ? item.get("posterUrl").s() : null);
                        video.setTrailerUrl(item.get("trailerUrl") != null ? item.get("trailerUrl").s() : null);
                        
                        // Map job tracking fields
                        video.setVideoJobId(item.get("videoJobId") != null ? item.get("videoJobId").s() : null);
                        video.setVideoJobStatus(item.get("videoJobStatus") != null ? item.get("videoJobStatus").s() : null);
                        video.setTrailerJobId(item.get("trailerJobId") != null ? item.get("trailerJobId").s() : null);
                        video.setTrailerJobStatus(item.get("trailerJobStatus") != null ? item.get("trailerJobStatus").s() : null);
                        
                        return video;
                    })
                    .collect(Collectors.toList());

        } catch (Exception e) {
            log.error("Error fetching all videos", e);
            throw new RuntimeException("Failed to fetch videos", e);
        }
    }

    // Basic createVideo method removed - use upload workflow instead
    // Users should use initiateUpload() followed by completeUpload()

    public Video processVideoUpload(String bucketName, String objectKey) {
        log.info("Processing video upload: bucket={}, key={}", bucketName, objectKey);

        try {
            // Extract metadata from S3 object
            Map<String, String> metadata = getS3ObjectMetadata(bucketName, objectKey);

            // Generate UUID for videoId
            String videoId = UUID.randomUUID().toString();

            // Extract title from metadata or use filename as fallback
            String title = extractTitle(metadata, objectKey);

            // Build access link using CloudFront URL pattern
            String videoUrl = buildAccessLink(objectKey);

            // Extract folder path and determine type/category
            String folderPath = extractFolderPath(objectKey);
            String type = determineType(objectKey);
            String category = determineCategory(folderPath);

            // Create Video object with new schema
            String now = Instant.now().toString();
            Video video = Video.builder()
                    .videoId(videoId)
                    .title(title)
                    .type(type)
                    .category(category)
                    .folderPath(folderPath)
                    .videoUrl(videoUrl)
                    .s3Key(objectKey)
                    .createdAt(now)
                    .modifiedAt(now)
                    .build();

            // Save to DynamoDB
            videoRepository.save(video);

            log.info("Successfully processed video: videoId={}, title={}", videoId, title);
            return video;

        } catch (Exception e) {
            log.error("Error processing video upload: bucket={}, key={}", bucketName, objectKey, e);
            throw new VideoProcessingException("Failed to process video upload: " + e.getMessage(), e);
        }
    }

    public Video updateVideo(String videoId, UpdateVideoRequest request) {
        log.info("Updating video metadata with ID: {}", videoId);

        try {
            Video video = getVideoById(videoId);

            // Update only non-null fields (metadata only - no folder path updates allowed)
            if (request.getTitle() != null) {
                video.setTitle(request.getTitle());
            }
            if (request.getType() != null) {
                video.setType(request.getType());
            }
            if (request.getCategory() != null) {
                video.setCategory(request.getCategory());
            }
            // Note: folderPath cannot be updated for existing videos
            // Note: posterUrl and trailerUrl should be updated via file update workflow

            video.setModifiedAt(Instant.now().toString());
            videoRepository.update(video);

            log.info("Successfully updated video metadata: videoId={}", videoId);
            return video;

        } catch (Exception e) {
            log.error("Error updating video with ID: {}", videoId, e);
            throw new RuntimeException("Failed to update video", e);
        }
    }

    /**
     * Initiate video file update - generates presigned URLs for updating specific
     * file types
     */
    public InitiateUploadResponse initiateFileUpdate(String videoId, InitiateFileUpdateRequest request) {
        log.info("Initiating file update for videoId: {} with posterUrl: {}, trailerUrl: {}, videoUrl: {}",
                videoId, request.isPosterUrl(), request.isTrailerUrl(), request.isVideoUrl());

        try {
            Video existingVideo = getVideoById(videoId);

            // Use existing folder path or allow override if provided
            String s3FolderPath;
            if (request.getFolderPath() != null && !request.getFolderPath().trim().isEmpty()) {
                // Build new folder path: category/provided-path/videoId
                s3FolderPath = buildS3FolderPath(existingVideo.getCategory(), request.getFolderPath(), videoId);
            } else {
                // Use existing folder path
                s3FolderPath = existingVideo.getFolderPath();
            }

            // Generate presigned URLs based on the requested types
            Map<String, String> uploadUrls = new HashMap<>();
            String primaryS3Key = s3FolderPath + "/main.mp4"; // Default to video

            if (request.isVideoUrl()) {
                uploadUrls.put("video", generatePresignedUrl(s3FolderPath + "/main.mp4"));
                primaryS3Key = s3FolderPath + "/main.mp4";
            }

            if (request.isPosterUrl()) {
                uploadUrls.put("poster", generatePresignedUrl(s3FolderPath + "/poster.jpg"));
                if (uploadUrls.size() == 1) { // If this is the only selected type
                    primaryS3Key = s3FolderPath + "/poster.jpg";
                }
            }

            if (request.isTrailerUrl()) {
                uploadUrls.put("trailer", generatePresignedUrl(s3FolderPath + "/trailer.mp4"));
                if (uploadUrls.size() == 1) { // If this is the only selected type
                    primaryS3Key = s3FolderPath + "/trailer.mp4";
                }
            }

            log.info("Generated file update URLs for videoId: {}, types: {}, primaryS3Key: {}",
                    videoId, uploadUrls.keySet(), primaryS3Key);

            return InitiateUploadResponse.builder()
                    .videoId(videoId)
                    .uploadUrls(uploadUrls)
                    .s3Key(primaryS3Key)
                    .folderPath(s3FolderPath)
                    .build();

        } catch (Exception e) {
            log.error("Error initiating file update for videoId: {}", videoId, e);
            throw new VideoProcessingException("Failed to initiate file update: " + e.getMessage(), e);
        }
    }

    /**
     * Complete file update - validates new files exist and updates metadata
     */
    public Video completeFileUpdate(String videoId, CompleteFileUpdateRequest request) {
        log.info("Completing file update for videoId: {}", videoId);

        try {
            Video existingVideo = getVideoById(videoId);
            String s3FolderPath = existingVideo.getFolderPath();

            // Update main video if provided
            if (request.isVideo()) {
                String mainVideoKey = s3FolderPath + "/main.mp4";
                if (!doesS3ObjectExist(mainVideoKey)) {
                    throw new VideoProcessingException("Updated main video file not found in S3: " + mainVideoKey);
                }
                existingVideo.setVideoUrl(buildAccessLink(mainVideoKey));
                existingVideo.setS3Key(mainVideoKey);
            }

            // Update poster if provided
            if (request.isPoster()) {
                String posterKey = s3FolderPath + "/poster.jpg";
                if (!doesS3ObjectExist(posterKey)) {
                    throw new VideoProcessingException("Updated poster file not found in S3: " + posterKey);
                }
                existingVideo.setPosterUrl(buildAccessLink(posterKey));
            }

            // Update trailer if provided
            if (request.isTrailer()) {
                String trailerKey = s3FolderPath + "/trailer.mp4";
                if (!doesS3ObjectExist(trailerKey)) {
                    throw new VideoProcessingException("Updated trailer file not found in S3: " + trailerKey);
                }
                existingVideo.setTrailerUrl(buildAccessLink(trailerKey));
            }

            // Update modification timestamp
            existingVideo.setModifiedAt(Instant.now().toString());

            // Save updated metadata to DynamoDB
            videoRepository.update(existingVideo);

            log.info("Successfully completed file update for videoId: {}", videoId);
            return existingVideo;

        } catch (VideoProcessingException e) {
            throw e; // Re-throw our custom exceptions
        } catch (Exception e) {
            log.error("Error completing file update for videoId: {}", videoId, e);
            throw new VideoProcessingException("Failed to complete file update: " + e.getMessage(), e);
        }
    }

    public void deleteVideo(String videoId) {
        log.info("Deleting video with ID: {}", videoId);

        try {
            Video video = getVideoById(videoId);

            // Delete entire S3 folder recursively if folderPath is present and bucket is
            // configured
            if (video.getFolderPath() != null && !video.getFolderPath().isEmpty() &&
                    videosBucketName != null && !videosBucketName.isEmpty()) {

                try {
                    // Delete all objects in the video's folder (main.mp4, poster.jpg, trailer.mp4,
                    // etc.)
                    String folderPrefix = video.getFolderPath() + "/";
                    deleteS3FolderRecursively(folderPrefix);

                    // Extract the parent folder path (category/folder-path) without the videoId
                    String parentFolderPath = extractParentFolderPath(video.getFolderPath());
                    if (parentFolderPath != null && !parentFolderPath.isEmpty()) {
                        // Check if parent folder is empty and delete if so
                        cleanupEmptyParentFolders(parentFolderPath);
                    }

                } catch (Exception s3e) {
                    log.warn("Failed to delete S3 folder: {}", video.getFolderPath(), s3e);
                    // Continue with DynamoDB deletion even if S3 deletion fails
                }
            }

            // Delete from transcoded S3 bucket if video has been transcoded
            if (isVideoTranscoded(video) && video.getFolderPath() != null && !video.getFolderPath().isEmpty() &&
                    transcodedBucketName != null && !transcodedBucketName.isEmpty()) {

                try {
                    // Delete transcoded files (HLS segments, .m3u8 files, etc.)
                    String folderPrefix = video.getFolderPath() + "/";
                    deleteS3FolderRecursively(folderPrefix, transcodedBucketName);
                    log.info("Successfully deleted transcoded files from S3: {}", video.getFolderPath());

                } catch (Exception s3e) {
                    log.warn("Failed to delete transcoded S3 folder: {}", video.getFolderPath(), s3e);
                    // Continue with DynamoDB deletion even if transcoded S3 deletion fails
                }
            }

            // Delete from DynamoDB
            videoRepository.deleteById(videoId);
            log.info("Successfully deleted video from DynamoDB: videoId={}", videoId);

        } catch (Exception e) {
            log.error("Error deleting video with ID: {}", videoId, e);
            throw new RuntimeException("Failed to delete video", e);
        }
    }

    public Video getVideoById(String videoId) {
        return videoRepository.findById(videoId)
                .orElseThrow(() -> new VideoNotFoundException("Video not found with id: " + videoId));
    }

    /**
     * Check if a video has been transcoded by examining if the URLs point to transcoded content
     */
    private boolean isVideoTranscoded(Video video) {
        // Check if videoUrl or trailerUrl contain transcoded bucket or .m3u8 files
        boolean videoTranscoded = video.getVideoUrl() != null && 
            (video.getVideoUrl().contains(".m3u8") || 
             (transcodedBucketName != null && video.getVideoUrl().contains(transcodedBucketName)));
        
        boolean trailerTranscoded = video.getTrailerUrl() != null && 
            (video.getTrailerUrl().contains(".m3u8") || 
             (transcodedBucketName != null && video.getTrailerUrl().contains(transcodedBucketName)));
        
        return videoTranscoded || trailerTranscoded;
    }

    // Helper methods
    private Map<String, String> getS3ObjectMetadata(String bucketName, String objectKey) {
        try {
            HeadObjectRequest headObjectRequest = HeadObjectRequest.builder()
                    .bucket(bucketName)
                    .key(objectKey)
                    .build();

            HeadObjectResponse headObjectResponse = s3Client.headObject(headObjectRequest);
            return headObjectResponse.metadata();

        } catch (S3Exception e) {
            log.error("S3 error retrieving object metadata: bucket={}, key={}", bucketName, objectKey, e);
            throw new S3OperationException("Failed to retrieve S3 object metadata: " + e.getMessage(), e);
        } catch (Exception e) {
            log.warn("Failed to retrieve S3 object metadata: bucket={}, key={}", bucketName, objectKey, e);
            return Map.of();
        }
    }

    private String extractTitle(Map<String, String> metadata, String objectKey) {
        // First, try to get title from metadata
        String title = metadata.get("title");
        if (title != null && !title.trim().isEmpty()) {
            return title.trim();
        }

        // Fallback: use filename without extension
        String filename = objectKey.substring(objectKey.lastIndexOf('/') + 1);
        int dotIndex = filename.lastIndexOf('.');
        if (dotIndex > 0) {
            filename = filename.substring(0, dotIndex);
        }

        // Replace underscores and hyphens with spaces, capitalize words
        return filename.replaceAll("[_-]", " ")
                .replaceAll("\\s+", " ")
                .trim();
    }

    private String buildAccessLink(String objectKey) {
        if (objectKey == null || objectKey.isEmpty()) {
            return "";
        }
        // Remove leading slash if present
        String cleanKey = objectKey.startsWith("/") ? objectKey.substring(1) : objectKey;
        return cloudfrontBaseUrl + "/" + cleanKey;
    }

    private String extractFolderPath(String objectKey) {
        int lastSlashIndex = objectKey.lastIndexOf('/');
        if (lastSlashIndex > 0) {
            return objectKey.substring(0, lastSlashIndex);
        }
        return ""; // Root folder
    }

    private String determineType(String objectKey) {
        String lowerKey = objectKey.toLowerCase();
        if (lowerKey.contains("trailer")) {
            return "trailer";
        } else if (lowerKey.contains("poster") || lowerKey.endsWith(".jpg") || lowerKey.endsWith(".png")) {
            return "poster";
        }
        return "video";
    }

    private String determineCategory(String folderPath) {
        if (folderPath == null || folderPath.isEmpty()) {
            return "movie"; // default
        }

        String lowerPath = folderPath.toLowerCase();
        if (lowerPath.contains("tv") || lowerPath.contains("series")) {
            return "tv";
        } else if (lowerPath.contains("live") || lowerPath.contains("stream")) {
            return "live";
        }
        return "movie"; // default
    }

    // ==================== NEW UPLOAD API METHODS ====================

    /**
     * Initiate upload process - generates presigned URLs and saves initial metadata
     */
    public InitiateUploadResponse initiateUpload(InitiateUploadRequest request) {
        log.info("Initiating upload for title: {}, category: {}", request.getTitle(), request.getCategory());

        try {
            // Generate unique video ID automatically
            String videoId = UUID.randomUUID().toString();

            // Build S3 folder structure based on category
            String s3FolderPath = buildS3FolderPath(request.getCategory(), request.getFolderPath(), videoId);

            // Save initial video metadata to DynamoDB for later completion
            String now = Instant.now().toString();
            Video initialVideo = Video.builder()
                    .videoId(videoId)
                    .title(request.getTitle())
                    .type("video") // main video type
                    .category(request.getCategory())
                    .folderPath(s3FolderPath)
                    .createdAt(now)
                    .modifiedAt(now)
                    // URLs will be set during completion
                    .build();

            // Save initial metadata
            videoRepository.save(initialVideo);

            // Generate presigned URLs only for requested file types
            Map<String, String> uploadUrls = new HashMap<>();
            String primaryS3Key = s3FolderPath + "/main.mp4"; // Default to video

            if (request.isVideoUrl()) {
                uploadUrls.put("video", generatePresignedUrl(s3FolderPath + "/main.mp4"));
            }

            if (request.isPosterUrl()) {
                uploadUrls.put("poster", generatePresignedUrl(s3FolderPath + "/poster.jpg"));
                if (uploadUrls.size() == 1) { // If this is the only selected type
                    primaryS3Key = s3FolderPath + "/poster.jpg";
                }
            }

            if (request.isTrailerUrl()) {
                uploadUrls.put("trailer", generatePresignedUrl(s3FolderPath + "/trailer.mp4"));
                if (uploadUrls.size() == 1) { // If this is the only selected type
                    primaryS3Key = s3FolderPath + "/trailer.mp4";
                }
            }

            log.info("Generated upload URLs for videoId: {}, types: {}, primaryS3Key: {}",
                    videoId, uploadUrls.keySet(), primaryS3Key);

            return InitiateUploadResponse.builder()
                    .videoId(videoId)
                    .uploadUrls(uploadUrls)
                    .s3Key(primaryS3Key)
                    .folderPath(s3FolderPath)
                    .build();

        } catch (Exception e) {
            log.error("Error initiating upload for title: {}", request.getTitle(), e);
            throw new VideoProcessingException("Failed to initiate upload: " + e.getMessage(), e);
        }
    }

    /**
     * Complete upload process - validates S3 objects exist and saves metadata to
     * DynamoDB. Requires metadata to be saved during initiate phase.
     */
    public Video completeUpload(CompleteUploadRequest request) {
        log.info("Completing upload for videoId: {}", request.getVideoId());

        try {
            // Check if video metadata already exists (from initiate phase)
            Video existingVideo;
            try {
                existingVideo = getVideoById(request.getVideoId());
            } catch (VideoNotFoundException e) {
                throw new VideoProcessingException(
                        "Video metadata not found. Please initiate upload first for videoId: " + request.getVideoId());
            }

            String s3FolderPath = existingVideo.getFolderPath();

            // Validate files exist in S3 if they were uploaded
            if (request.isVideo()) {
                String mainVideoKey = s3FolderPath + "/main.mp4";
                if (!doesS3ObjectExist(mainVideoKey)) {
                    throw new VideoProcessingException("Main video file not found in S3: " + mainVideoKey);
                }
                existingVideo.setVideoUrl(buildAccessLink(mainVideoKey));
                existingVideo.setS3Key(mainVideoKey);
            }

            if (request.isPoster()) {
                String posterKey = s3FolderPath + "/poster.jpg";
                if (!doesS3ObjectExist(posterKey)) {
                    throw new VideoProcessingException("Poster file not found in S3: " + posterKey);
                }
                existingVideo.setPosterUrl(buildAccessLink(posterKey));
            }

            if (request.isTrailer()) {
                String trailerKey = s3FolderPath + "/trailer.mp4";
                if (!doesS3ObjectExist(trailerKey)) {
                    throw new VideoProcessingException("Trailer file not found in S3: " + trailerKey);
                }
                existingVideo.setTrailerUrl(buildAccessLink(trailerKey));
            }

            // Update modification timestamp
            existingVideo.setModifiedAt(Instant.now().toString());

            // Save updated metadata to DynamoDB
            videoRepository.update(existingVideo);

            log.info("Successfully completed upload for videoId: {}", request.getVideoId());
            return existingVideo;

        } catch (VideoProcessingException e) {
            throw e; // Re-throw our custom exceptions
        } catch (Exception e) {
            log.error("Error completing upload for videoId: {}", request.getVideoId(), e);
            throw new VideoProcessingException("Failed to complete upload: " + e.getMessage(), e);
        }
    }

    // ==================== HELPER METHODS ====================

    private String buildS3FolderPath(String category, String folderPath, String videoId) {
        // Structure: category/folderPath/videoId (e.g., tv/breaking-bad/season-1/uuid)
        // Include category in the folder structure
        return String.format("%s/%s/%s", category, folderPath.replaceAll("^/+", ""), videoId);
    }

    private String generatePresignedUrl(String s3Key) {
        try {
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(videosBucketName)
                    .key(s3Key)
                    .build();

            PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                    .signatureDuration(Duration.ofMinutes(15)) // 15 minute expiry
                    .putObjectRequest(putObjectRequest)
                    .build();

            PresignedPutObjectRequest presignedRequest = s3Presigner.presignPutObject(presignRequest);

            return presignedRequest.url().toString();

        } catch (Exception e) {
            log.error("Error generating presigned URL for s3Key: {}", s3Key, e);
            throw new S3OperationException("Failed to generate presigned URL: " + e.getMessage(), e);
        }
    }

    private boolean doesS3ObjectExist(String s3Key) {
        try {
            HeadObjectRequest headObjectRequest = HeadObjectRequest.builder()
                    .bucket(videosBucketName)
                    .key(s3Key)
                    .build();

            s3Client.headObject(headObjectRequest);
            return true;

        } catch (NoSuchKeyException e) {
            log.debug("S3 object does not exist: {}", s3Key);
            return false;
        } catch (S3Exception e) {
            log.error("S3 error checking object existence: {}", s3Key, e);
            throw new S3OperationException("Failed to check S3 object existence: " + e.getMessage(), e);
        } catch (Exception e) {
            log.error("Unexpected error checking S3 object existence: {}", s3Key, e);
            return false;
        }
    }

    /**
     * Delete entire S3 folder recursively
     */
    private void deleteS3FolderRecursively(String folderPrefix) {
        try {
            // List all objects with the folder prefix
            ListObjectsV2Request listRequest = ListObjectsV2Request.builder()
                    .bucket(videosBucketName)
                    .prefix(folderPrefix)
                    .build();

            ListObjectsV2Response listResponse = s3Client.listObjectsV2(listRequest);

            if (listResponse.contents().isEmpty()) {
                log.info("No objects found in folder: {}", folderPrefix);
                return;
            }

            // Delete all objects in batch
            List<ObjectIdentifier> objectsToDelete = listResponse.contents().stream()
                    .map(s3Object -> ObjectIdentifier.builder().key(s3Object.key()).build())
                    .collect(Collectors.toList());

            if (!objectsToDelete.isEmpty()) {
                Delete delete = Delete.builder()
                        .objects(objectsToDelete)
                        .build();

                DeleteObjectsRequest deleteRequest = DeleteObjectsRequest.builder()
                        .bucket(videosBucketName)
                        .delete(delete)
                        .build();

                DeleteObjectsResponse deleteResponse = s3Client.deleteObjects(deleteRequest);
                log.info("Deleted {} objects from folder: {}", deleteResponse.deleted().size(), folderPrefix);
            }

        } catch (Exception e) {
            log.error("Error deleting S3 folder recursively: {}", folderPrefix, e);
            throw new S3OperationException("Failed to delete S3 folder recursively: " + e.getMessage(), e);
        }
    }

    /**
     * Delete entire S3 folder recursively from specified bucket
     */
    private void deleteS3FolderRecursively(String folderPrefix, String bucketName) {
        try {
            // List all objects with the folder prefix
            ListObjectsV2Request listRequest = ListObjectsV2Request.builder()
                    .bucket(bucketName)
                    .prefix(folderPrefix)
                    .build();

            ListObjectsV2Response listResponse = s3Client.listObjectsV2(listRequest);

            if (listResponse.contents().isEmpty()) {
                log.info("No objects found in folder: {} in bucket: {}", folderPrefix, bucketName);
                return;
            }

            // Delete all objects in batch
            List<ObjectIdentifier> objectsToDelete = listResponse.contents().stream()
                    .map(s3Object -> ObjectIdentifier.builder().key(s3Object.key()).build())
                    .collect(Collectors.toList());

            if (!objectsToDelete.isEmpty()) {
                Delete delete = Delete.builder()
                        .objects(objectsToDelete)
                        .build();

                DeleteObjectsRequest deleteRequest = DeleteObjectsRequest.builder()
                        .bucket(bucketName)
                        .delete(delete)
                        .build();

                DeleteObjectsResponse deleteResponse = s3Client.deleteObjects(deleteRequest);
                log.info("Deleted {} objects from folder: {} in bucket: {}", 
                        deleteResponse.deleted().size(), folderPrefix, bucketName);
            }

        } catch (Exception e) {
            log.error("Error deleting S3 folder recursively from bucket {}: {}", bucketName, folderPrefix, e);
            throw new S3OperationException("Failed to delete S3 folder recursively from bucket " + bucketName + ": " + e.getMessage(), e);
        }
    }

    /**
     * Extract parent folder path from full folder path
     * Example: tv/breaking-bad/season-1/uuid -> tv/breaking-bad/season-1
     */
    private String extractParentFolderPath(String fullFolderPath) {
        if (fullFolderPath == null || fullFolderPath.isEmpty()) {
            return null;
        }

        int lastSlashIndex = fullFolderPath.lastIndexOf('/');
        if (lastSlashIndex > 0) {
            return fullFolderPath.substring(0, lastSlashIndex);
        }

        return null; // No parent folder
    }

    /**
     * Clean up empty parent folders recursively
     * Example: If tv/breaking-bad/season-1 is empty, delete it and check if
     * tv/breaking-bad is empty
     */
    private void cleanupEmptyParentFolders(String folderPath) {
        try {
            // Check if folder is empty
            if (isS3FolderEmpty(folderPath + "/")) {
                log.info("Folder is empty, attempting cleanup: {}", folderPath);

                // Try to delete the folder (which should be empty)
                deleteS3FolderRecursively(folderPath + "/");

                // Recursively check parent folder
                String parentPath = extractParentFolderPath(folderPath);
                if (parentPath != null && !parentPath.isEmpty()) {
                    cleanupEmptyParentFolders(parentPath);
                }
            } else {
                log.debug("Folder is not empty, skipping cleanup: {}", folderPath);
            }
        } catch (Exception e) {
            log.warn("Error during parent folder cleanup: {}", folderPath, e);
            // Don't throw exception as this is cleanup operation
        }
    }

    /**
     * Check if S3 folder is empty
     */
    private boolean isS3FolderEmpty(String folderPrefix) {
        try {
            ListObjectsV2Request listRequest = ListObjectsV2Request.builder()
                    .bucket(videosBucketName)
                    .prefix(folderPrefix)
                    .maxKeys(1) // Only need to check if any object exists
                    .build();

            ListObjectsV2Response listResponse = s3Client.listObjectsV2(listRequest);
            return listResponse.contents().isEmpty();

        } catch (Exception e) {
            log.warn("Error checking if S3 folder is empty: {}", folderPrefix, e);
            return false; // Assume not empty if we can't check
        }
    }

    /**
     * Updates video job status when MediaConvert job starts.
     * 
     * @param objectKey the S3 object key
     * @param jobId the MediaConvert job ID
     * @param status the job status
     * @param isTrailer whether this is a trailer
     */
    public void updateVideoJobStatus(String objectKey, String jobId, String status, boolean isTrailer) {
        try {
            // Find video by S3 key or create a new entry
            String videoId = extractVideoIdFromObjectKey(objectKey);
            Video video = videoRepository.findById(videoId).orElse(null);
            
            if (video == null) {
                // Create a new video entry if it doesn't exist
                video = Video.builder()
                    .videoId(videoId)
                    .title(extractTitleFromObjectKey(objectKey))
                    .type("video")
                    .category("movie") // Default category
                    .folderPath(extractFolderPathFromObjectKey(objectKey))
                    .videoUrl("")
                    .s3Key(objectKey)
                    .createdAt(Instant.now().toString())
                    .build();
            }
            
            // Update job tracking fields
            if (isTrailer) {
                video.setTrailerJobId(jobId);
                video.setTrailerJobStatus(status);
            } else {
                video.setVideoJobId(jobId);
                video.setVideoJobStatus(status);
            }
            
            video.setModifiedAt(Instant.now().toString());
            videoRepository.save(video);
            
            log.info("Updated video job status: videoId={}, jobId={}, status={}, isTrailer={}", 
                    videoId, jobId, status, isTrailer);
                    
        } catch (Exception e) {
            log.error("Failed to update video job status: objectKey={}, jobId={}", objectKey, jobId, e);
            throw new VideoProcessingException("Failed to update video job status", e);
        }
    }

    /**
     * Updates video URLs when MediaConvert job completes successfully.
     * 
     * @param jobId the MediaConvert job ID
     * @param m3u8Url the HLS playlist URL
     * @param isTrailer whether this is a trailer
     * @param sourceKey the original source key
     */
    public void updateVideoJobComplete(String jobId, String m3u8Url, boolean isTrailer, String sourceKey) {
        try {
            // Find video by job ID
            Video video = findVideoByJobId(jobId, isTrailer);
            
            if (video == null) {
                log.warn("Video not found for job ID: {}, isTrailer: {}", jobId, isTrailer);
                return;
            }
            
            // Update URLs and status
            if (isTrailer) {
                video.setTrailerUrl(m3u8Url);
                video.setTrailerJobStatus("Completed");
            } else {
                video.setVideoUrl(m3u8Url);
                video.setVideoJobStatus("Completed");
            }
            
            video.setModifiedAt(Instant.now().toString());
            videoRepository.save(video);
            
            log.info("Updated video job completion: videoId={}, jobId={}, m3u8Url={}, isTrailer={}", 
                    video.getVideoId(), jobId, m3u8Url, isTrailer);
                    
        } catch (Exception e) {
            log.error("Failed to update video job completion: jobId={}, isTrailer={}", jobId, isTrailer, e);
            throw new VideoProcessingException("Failed to update video job completion", e);
        }
    }

    /**
     * Updates video job status when MediaConvert job fails.
     * 
     * @param jobId the MediaConvert job ID
     * @param errorMessage the error message
     * @param isTrailer whether this is a trailer
     * @param sourceKey the original source key
     */
    public void updateVideoJobError(String jobId, String errorMessage, boolean isTrailer, String sourceKey) {
        try {
            // Find video by job ID
            Video video = findVideoByJobId(jobId, isTrailer);
            
            if (video == null) {
                log.warn("Video not found for job ID: {}, isTrailer: {}", jobId, isTrailer);
                return;
            }
            
            // Update status to failed
            if (isTrailer) {
                video.setTrailerJobStatus("Failed: " + errorMessage);
            } else {
                video.setVideoJobStatus("Failed: " + errorMessage);
            }
            
            video.setModifiedAt(Instant.now().toString());
            videoRepository.save(video);
            
            log.info("Updated video job error: videoId={}, jobId={}, error={}, isTrailer={}", 
                    video.getVideoId(), jobId, errorMessage, isTrailer);
                    
        } catch (Exception e) {
            log.error("Failed to update video job error: jobId={}, isTrailer={}", jobId, isTrailer, e);
            throw new VideoProcessingException("Failed to update video job error", e);
        }
    }

    /**
     * Finds a video by MediaConvert job ID.
     * 
     * @param jobId the job ID
     * @param isTrailer whether this is a trailer job
     * @return the video or null if not found
     */
    private Video findVideoByJobId(String jobId, boolean isTrailer) {
        try {
            // Scan the table to find video with matching job ID
            // Note: In production, consider using a GSI for job ID lookups
            ScanRequest scanRequest = ScanRequest.builder()
                .tableName(videosTableName)
                .filterExpression(isTrailer ? "trailerJobId = :jobId" : "videoJobId = :jobId")
                .expressionAttributeValues(Map.of(":jobId", 
                    software.amazon.awssdk.services.dynamodb.model.AttributeValue.builder()
                        .s(jobId)
                        .build()))
                .build();

            ScanResponse response = dynamoDbClient.scan(scanRequest);
            
            if (response.items().isEmpty()) {
                return null;
            }

            // Convert first item to Video object
            Map<String, software.amazon.awssdk.services.dynamodb.model.AttributeValue> item = response.items().get(0);
            String videoId = item.get("videoId").s();
            return videoRepository.findById(videoId).orElse(null);
            
        } catch (Exception e) {
            log.error("Failed to find video by job ID: {}, isTrailer: {}", jobId, isTrailer, e);
            return null;
        }
    }

    /**
     * Extracts video ID from S3 object key.
     * The video ID is the folder name that contains the video files.
     * 
     * @param objectKey the S3 object key (e.g., "movie/test-movies/automated-test/e05f9ee0-177f-42f0-8cfd-08a36d7269c3/main.mp4")
     * @return the video ID (e.g., "e05f9ee0-177f-42f0-8cfd-08a36d7269c3")
     */
    private String extractVideoIdFromObjectKey(String objectKey) {
        // Extract the video ID from the path structure: category/folderPath/videoId/filename
        String[] pathParts = objectKey.split("/");
        if (pathParts.length >= 2) {
            // The video ID is the second-to-last part of the path (the folder containing the files)
            return pathParts[pathParts.length - 2];
        }
        
        // Fallback: Extract the filename without extension to use as video ID
        String fileName = objectKey.substring(objectKey.lastIndexOf('/') + 1);
        if (fileName.contains(".")) {
            fileName = fileName.substring(0, fileName.lastIndexOf('.'));
        }
        // Remove 'trailer' suffix if present to get the base ID
        if (fileName.toLowerCase().endsWith("_trailer") || fileName.toLowerCase().endsWith("-trailer")) {
            fileName = fileName.substring(0, fileName.lastIndexOf('_') > 0 ? fileName.lastIndexOf('_') : fileName.lastIndexOf('-'));
        }
        return fileName;
    }

    /**
     * Extracts title from S3 object key.
     * 
     * @param objectKey the S3 object key
     * @return the title
     */
    private String extractTitleFromObjectKey(String objectKey) {
        String fileName = objectKey.substring(objectKey.lastIndexOf('/') + 1);
        if (fileName.contains(".")) {
            fileName = fileName.substring(0, fileName.lastIndexOf('.'));
        }
        // Convert underscores and hyphens to spaces and capitalize
        return fileName.replaceAll("[_-]", " ").trim();
    }

    /**
     * Extracts folder path from S3 object key.
     * 
     * @param objectKey the S3 object key
     * @return the folder path
     */
    private String extractFolderPathFromObjectKey(String objectKey) {
        int lastSlashIndex = objectKey.lastIndexOf('/');
        return lastSlashIndex > 0 ? objectKey.substring(0, lastSlashIndex) : "";
    }

    /**
     * Converts a Video entity to VideoDetailResponse with structured process information.
     * 
     * @param video the video entity to convert
     * @return VideoDetailResponse with process array
     */
    public VideoDetailResponse convertToDetailResponse(Video video) {
        List<VideoDetailResponse.ProcessInfo> processes = List.of(
            VideoDetailResponse.ProcessInfo.builder()
                .mediaType("video")
                .jobId(video.getVideoJobId())
                .jobStatus(video.getVideoJobStatus())
                .build(),
            VideoDetailResponse.ProcessInfo.builder()
                .mediaType("trailer")
                .jobId(video.getTrailerJobId())
                .jobStatus(video.getTrailerJobStatus())
                .build()
        );

        return VideoDetailResponse.builder()
            .videoId(video.getVideoId())
            .title(video.getTitle())
            .type(video.getType())
            .category(video.getCategory())
            .folderPath(video.getFolderPath())
            .createdAt(video.getCreatedAt())
            .modifiedAt(video.getModifiedAt())
            .s3Key(video.getS3Key())
            .posterUrl(video.getPosterUrl())
            .trailerUrl(video.getTrailerUrl())
            .videoUrl(video.getVideoUrl())
            .process(processes)
            .build();
    }
}
