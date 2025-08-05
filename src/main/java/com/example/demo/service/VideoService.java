package com.example.demo.service;

import com.example.demo.dto.request.UpdateVideoRequest;
import com.example.demo.dto.request.InitiateUploadRequest;
import com.example.demo.dto.request.InitiateFileUpdateRequest;
import com.example.demo.dto.request.CompleteUploadRequest;
import com.example.demo.dto.request.CompleteFileUpdateRequest;
import com.example.demo.dto.response.InitiateUploadResponse;
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
                        video.setAccessLink(item.get("accessLink") != null ? item.get("accessLink").s() : "");
                        video.setCreatedAt(item.get("createdAt") != null ? item.get("createdAt").s() : "");
                        video.setModifiedAt(item.get("modifiedAt") != null ? item.get("modifiedAt").s() : "");
                        video.setS3Key(item.get("s3Key") != null ? item.get("s3Key").s() : "");
                        video.setPosterUrl(item.get("posterUrl") != null ? item.get("posterUrl").s() : null);
                        video.setTrailerUrl(item.get("trailerUrl") != null ? item.get("trailerUrl").s() : null);
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
            String accessLink = buildAccessLink(objectKey);

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
                    .accessLink(accessLink)
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
     * Initiate video file update - generates presigned URLs for updating video files
     */
    public InitiateUploadResponse initiateFileUpdate(String videoId, InitiateUploadRequest request) {
        log.info("Initiating file update for videoId: {}", videoId);

        try {
            Video existingVideo = getVideoById(videoId);
            
            // Use existing folder path structure - cannot be changed during update
            String s3FolderPath = existingVideo.getFolderPath();
            
            // Generate presigned URLs for requested file updates
            Map<String, String> uploadUrls = new HashMap<>();
            
            // Always allow main video update
            uploadUrls.put("video", generatePresignedUrl(s3FolderPath + "/main.mp4"));
            
            // Only generate URLs for requested file types
            if (request.isIncludePoster()) {
                uploadUrls.put("poster", generatePresignedUrl(s3FolderPath + "/poster.jpg"));
            }
            
            if (request.isIncludeTrailer()) {
                uploadUrls.put("trailer", generatePresignedUrl(s3FolderPath + "/trailer.mp4"));
            }

            String primaryS3Key = s3FolderPath + "/main.mp4";

            log.info("Generated file update URLs for videoId: {}, s3Key: {}", videoId, primaryS3Key);

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
     * Initiate video file update with simplified request - generates presigned URLs for updating specific file types
     */
    public InitiateUploadResponse initiateFileUpdate(String videoId, InitiateFileUpdateRequest request) {
        log.info("Initiating file update for videoId: {} with video:{}, poster:{}, trailer:{}", 
                videoId, request.isIncludeVideo(), request.isIncludePoster(), request.isIncludeTrailer());

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
            
            if (request.isIncludeVideo()) {
                uploadUrls.put("video", generatePresignedUrl(s3FolderPath + "/main.mp4"));
                primaryS3Key = s3FolderPath + "/main.mp4";
            }
            
            if (request.isIncludePoster()) {
                uploadUrls.put("poster", generatePresignedUrl(s3FolderPath + "/poster.jpg"));
                if (uploadUrls.size() == 1) { // If this is the only selected type
                    primaryS3Key = s3FolderPath + "/poster.jpg";
                }
            }
            
            if (request.isIncludeTrailer()) {
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

            // Validate files exist in S3 if they were updated
            String mainVideoKey = s3FolderPath + "/main.mp4";
            if (!doesS3ObjectExist(mainVideoKey)) {
                throw new VideoProcessingException("Updated main video file not found in S3: " + mainVideoKey);
            }
            
            // Update access link since main video was updated
            existingVideo.setAccessLink(buildAccessLink(mainVideoKey));
            existingVideo.setS3Key(mainVideoKey);

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

            // Delete entire S3 folder recursively if folderPath is present and bucket is configured
            if (video.getFolderPath() != null && !video.getFolderPath().isEmpty() &&
                    videosBucketName != null && !videosBucketName.isEmpty()) {

                try {
                    // Delete all objects in the video's folder (main.mp4, poster.jpg, trailer.mp4, etc.)
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
     * Initiate upload process - generates presigned URLs for video, poster, and
     * trailer
     */
    public InitiateUploadResponse initiateUpload(InitiateUploadRequest request) {
        log.info("Initiating upload for title: {}, category: {}", request.getTitle(), request.getCategory());

        try {
            // Generate unique video ID
            String videoId = UUID.randomUUID().toString();

            // Build S3 folder structure based on category
            String s3FolderPath = buildS3FolderPath(request.getCategory(), request.getFolderPath(), videoId);

            // Generate presigned URLs
            Map<String, String> uploadUrls = new HashMap<>();
            uploadUrls.put("video", generatePresignedUrl(s3FolderPath + "/main.mp4"));

            // Only generate URLs for requested file types
            if (request.isIncludePoster()) {
                uploadUrls.put("poster", generatePresignedUrl(s3FolderPath + "/poster.jpg"));
            }

            if (request.isIncludeTrailer()) {
                uploadUrls.put("trailer", generatePresignedUrl(s3FolderPath + "/trailer.mp4"));
            }

            String primaryS3Key = s3FolderPath + "/main.mp4";

            log.info("Generated upload URLs for videoId: {}, s3Key: {}", videoId, primaryS3Key);

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
     * DynamoDB
     */
    public Video completeUpload(CompleteUploadRequest request) {
        log.info("Completing upload for videoId: {}", request.getVideoId());

        try {
            // Build S3 folder path
            String s3FolderPath = buildS3FolderPath(request.getCategory(), request.getFolderPath(),
                    request.getVideoId());

            // Validate required files exist in S3
            String mainVideoKey = s3FolderPath + "/main.mp4";
            if (!doesS3ObjectExist(mainVideoKey)) {
                throw new VideoProcessingException("Main video file not found in S3: " + mainVideoKey);
            }

            // Validate optional files if specified
            if (request.isPoster()) {
                String posterKey = s3FolderPath + "/poster.jpg";
                if (!doesS3ObjectExist(posterKey)) {
                    throw new VideoProcessingException("Poster file not found in S3: " + posterKey);
                }
            }

            if (request.isTrailer()) {
                String trailerKey = s3FolderPath + "/trailer.mp4";
                if (!doesS3ObjectExist(trailerKey)) {
                    throw new VideoProcessingException("Trailer file not found in S3: " + trailerKey);
                }
            }

            // All validations passed - create Video metadata
            String now = Instant.now().toString();
            String accessLink = buildAccessLink(mainVideoKey);

            Video video = Video.builder()
                    .videoId(request.getVideoId())
                    .title(request.getTitle())
                    .type("video") // main video type
                    .category(request.getCategory())
                    .folderPath(s3FolderPath)
                    .accessLink(accessLink)
                    .s3Key(mainVideoKey)
                    .createdAt(now)
                    .modifiedAt(now)
                    .posterUrl(request.isPoster() ? buildAccessLink(s3FolderPath + "/poster.jpg") : null)
                    .trailerUrl(request.isTrailer() ? buildAccessLink(s3FolderPath + "/trailer.mp4") : null)
                    .build();

            // Save to DynamoDB
            videoRepository.save(video);

            log.info("Successfully completed upload for videoId: {}", request.getVideoId());
            return video;

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
     * Example: If tv/breaking-bad/season-1 is empty, delete it and check if tv/breaking-bad is empty
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
}
