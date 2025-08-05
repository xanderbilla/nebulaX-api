package com.example.demo.controller;

import com.example.demo.dto.common.ApiResponse;
import com.example.demo.dto.request.UpdateVideoRequest;
import com.example.demo.dto.request.InitiateUploadRequest;
import com.example.demo.dto.request.CompleteUploadRequest;
import com.example.demo.dto.response.InitiateUploadResponse;
import com.example.demo.model.Video;
import com.example.demo.service.VideoService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;
import java.util.List;

@Slf4j
@RestController
@RequestMapping("${app.api.base-path}/videos")
@RequiredArgsConstructor
public class VideoController {

    private final VideoService videoService;

    @GetMapping
    public ResponseEntity<ApiResponse<List<Video>>> getAllVideos() {
        log.info("Fetching all videos");

        try {
            List<Video> videos = videoService.getAllVideos();

            ApiResponse<List<Video>> response = ApiResponse.success(
                    "Videos retrieved successfully", videos);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Error fetching all videos", e);

            ApiResponse<List<Video>> errorResponse = ApiResponse.error(
                    "Failed to fetch videos: " + e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR.value());

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @GetMapping("/{videoId}")
    public ResponseEntity<ApiResponse<Video>> getVideo(@PathVariable String videoId) {
        log.info("Fetching video with ID: {}", videoId);

        try {
            Video video = videoService.getVideoById(videoId);

            ApiResponse<Video> response = ApiResponse.success("Video retrieved successfully", video);

            return ResponseEntity.ok(response);

        } catch (RuntimeException e) {
            log.error("Error fetching video with ID: {}", videoId, e);

            ApiResponse<Video> errorResponse = ApiResponse.error(e.getMessage(), HttpStatus.NOT_FOUND.value());

            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
        }
    }

    // Basic create video endpoint removed - use upload workflow instead
    // Users should use POST /videos/upload/initiate followed by POST
    // /videos/upload/complete

    @PutMapping("/{videoId}")
    public ResponseEntity<ApiResponse<Video>> updateVideo(
            @PathVariable String videoId,
            @Valid @RequestBody UpdateVideoRequest request) {

        log.info("Updating video with ID: {}", videoId);

        try {
            Video video = videoService.updateVideo(videoId, request);

            ApiResponse<Video> response = ApiResponse.success("Video updated successfully", video);

            return ResponseEntity.ok(response);

        } catch (RuntimeException e) {
            log.error("Error updating video with ID: {}", videoId, e);

            ApiResponse<Video> errorResponse = ApiResponse.error(e.getMessage(), HttpStatus.NOT_FOUND.value());

            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
        } catch (Exception e) {
            log.error("Error updating video with ID: {}", videoId, e);

            ApiResponse<Video> errorResponse = ApiResponse.error(
                    "Failed to update video: " + e.getMessage(),
                    HttpStatus.BAD_REQUEST.value());

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        }
    }

    @DeleteMapping("/{videoId}")
    public ResponseEntity<ApiResponse<String>> deleteVideo(@PathVariable String videoId) {
        log.info("Deleting video with ID: {}", videoId);

        try {
            videoService.deleteVideo(videoId);

            ApiResponse<String> response = ApiResponse.success("Video deleted successfully", videoId);

            return ResponseEntity.ok(response);

        } catch (RuntimeException e) {
            log.error("Error deleting video with ID: {}", videoId, e);

            ApiResponse<String> errorResponse = ApiResponse.error(e.getMessage(), HttpStatus.NOT_FOUND.value());

            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
        }
    }

    // ==================== NEW UPLOAD WORKFLOW ENDPOINTS ====================

    /**
     * POST /videos/upload/initiate
     * Initiates upload process and returns presigned URLs
     */
    @PostMapping("/upload/initiate")
    public ResponseEntity<ApiResponse<InitiateUploadResponse>> initiateUpload(
            @Valid @RequestBody InitiateUploadRequest request) {
        log.info("Initiating upload for title: {}, category: {}", request.getTitle(), request.getCategory());

        try {
            InitiateUploadResponse uploadResponse = videoService.initiateUpload(request);

            ApiResponse<InitiateUploadResponse> response = ApiResponse.success(
                    "Upload initiated successfully", uploadResponse);

            return ResponseEntity.status(HttpStatus.CREATED).body(response);

        } catch (Exception e) {
            log.error("Error initiating upload for title: {}", request.getTitle(), e);

            ApiResponse<InitiateUploadResponse> errorResponse = ApiResponse.error(
                    "Failed to initiate upload: " + e.getMessage(),
                    HttpStatus.BAD_REQUEST.value());

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        }
    }

    /**
     * POST /videos/upload/complete
     * Completes upload process after files are uploaded to S3
     */
    @PostMapping("/upload/complete")
    public ResponseEntity<ApiResponse<Video>> completeUpload(
            @Valid @RequestBody CompleteUploadRequest request) {
        log.info("Completing upload for videoId: {}", request.getVideoId());

        try {
            Video video = videoService.completeUpload(request);

            ApiResponse<Video> response = ApiResponse.success(
                    "Upload completed successfully", video);

            return ResponseEntity.status(HttpStatus.CREATED).body(response);

        } catch (Exception e) {
            log.error("Error completing upload for videoId: {}", request.getVideoId(), e);

            ApiResponse<Video> errorResponse = ApiResponse.error(
                    "Failed to complete upload: " + e.getMessage(),
                    HttpStatus.BAD_REQUEST.value());

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        }
    }
}
