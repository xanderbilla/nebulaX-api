package com.example.demo.controller;

import com.example.demo.dto.common.ApiResponse;
import com.example.demo.dto.request.UpdateVideoRequest;
import com.example.demo.dto.request.InitiateUploadRequest;
import com.example.demo.dto.request.InitiateFileUpdateRequest;
import com.example.demo.dto.request.CompleteUploadRequest;
import com.example.demo.dto.request.CompleteFileUpdateRequest;
import com.example.demo.dto.response.InitiateUploadResponse;
import com.example.demo.dto.response.VideoDetailResponse;
import com.example.demo.model.Video;
import com.example.demo.service.VideoService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;
import java.util.List;

/**
 * REST Controller for video management operations.
 * 
 * @author Vikas Singh
 * @since August 3, 2025
 */
@Slf4j
@RestController
@RequestMapping("${app.api.base-path}/videos")
@RequiredArgsConstructor
public class VideoController {

    private final VideoService videoService;

    /**
     * Retrieves all videos from the system.
     * 
     * @return ResponseEntity containing list of all videos with consistent process
     *         information
     */
    @GetMapping
    public ResponseEntity<ApiResponse<List<VideoDetailResponse>>> getAllVideos() {
        log.info("Fetching all videos");

        try {
            List<Video> videos = videoService.getAllVideos();
            List<VideoDetailResponse> videoResponses = videos.stream()
                    .map(videoService::convertToDetailResponse)
                    .toList();

            ApiResponse<List<VideoDetailResponse>> response = ApiResponse.success(
                    "Videos retrieved successfully", videoResponses);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Error fetching all videos", e);

            ApiResponse<List<VideoDetailResponse>> errorResponse = ApiResponse.error(
                    "Failed to fetch videos: " + e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR.value());

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    /**
     * Retrieves a specific video by its ID.
     * 
     * @param videoId The unique identifier of the video
     * @return ResponseEntity containing the requested video with process
     *         information
     */
    @GetMapping("/{videoId}")
    public ResponseEntity<ApiResponse<VideoDetailResponse>> getVideo(@PathVariable String videoId) {
        log.info("Fetching video with ID: {}", videoId);

        try {
            Video video = videoService.getVideoById(videoId);
            VideoDetailResponse detailResponse = videoService.convertToDetailResponse(video);

            ApiResponse<VideoDetailResponse> response = ApiResponse.success("Video retrieved successfully",
                    detailResponse);

            return ResponseEntity.ok(response);

        } catch (RuntimeException e) {
            log.error("Error fetching video with ID: {}", videoId, e);

            ApiResponse<VideoDetailResponse> errorResponse = ApiResponse.error(e.getMessage(),
                    HttpStatus.NOT_FOUND.value());

            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
        }
    }

    /**
     * Updates an existing video's metadata.
     * 
     * @param videoId The unique identifier of the video to update
     * @param request The update request containing new video metadata
     * @return ResponseEntity containing the updated video
     */
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

    /**
     * Deletes a video from the system.
     * 
     * @param videoId The unique identifier of the video to delete
     * @return ResponseEntity with deletion confirmation message
     */
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

    /**
     * Initiates upload process and returns presigned URLs for specified file types.
     * 
     * @param request The upload initiation request containing metadata and file
     *                type flags
     * @return ResponseEntity containing presigned URLs for requested file types
     */
    @PostMapping("/upload/initiate")
    public ResponseEntity<ApiResponse<InitiateUploadResponse>> initiateUpload(
            @Valid @RequestBody InitiateUploadRequest request) {
        log.info("Initiating upload for title: {}, category: {}, posterUrl: {}, trailerUrl: {}, videoUrl: {}",
                request.getTitle(), request.getCategory(),
                request.isPosterUrl(), request.isTrailerUrl(), request.isVideoUrl());

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
     * Completes upload process after files are uploaded to S3.
     * 
     * @param request The upload completion request with videoId and file type flags
     * @return ResponseEntity containing the completed video
     */
    @PostMapping("/upload/complete")
    public ResponseEntity<ApiResponse<Video>> completeUpload(
            @Valid @RequestBody CompleteUploadRequest request) {
        log.info("Completing upload for videoId: {}, poster: {}, trailer: {}, video: {}",
                request.getVideoId(), request.isPoster(), request.isTrailer(), request.isVideo());

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

    /**
     * Initiates file update process and returns presigned URLs for updating video
     * files.
     * 
     * @param request The file update initiation request with videoId and file type
     *                flags
     * @return ResponseEntity containing presigned URLs for requested file types
     */
    @PostMapping("/update/initiate")
    public ResponseEntity<ApiResponse<InitiateUploadResponse>> initiateFileUpdate(
            @Valid @RequestBody InitiateFileUpdateRequest request) {
        log.info("Initiating file update for videoId: {} with posterUrl: {}, trailerUrl: {}, videoUrl: {}",
                request.getVideoId(), request.isPosterUrl(), request.isTrailerUrl(), request.isVideoUrl());

        try {
            InitiateUploadResponse uploadResponse = videoService.initiateFileUpdate(request.getVideoId(), request);

            ApiResponse<InitiateUploadResponse> response = ApiResponse.success(
                    "File update initiated successfully", uploadResponse);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Error initiating file update for videoId: {}", request.getVideoId(), e);

            ApiResponse<InitiateUploadResponse> errorResponse = ApiResponse.error(
                    "Failed to initiate file update: " + e.getMessage(),
                    HttpStatus.BAD_REQUEST.value());

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        }
    }

    /**
     * Completes file update process after new files are uploaded to S3.
     * 
     * @param request The file update completion request with videoId and file type
     *                flags
     * @return ResponseEntity containing the updated video
     */
    @PostMapping("/update/complete")
    public ResponseEntity<ApiResponse<Video>> completeFileUpdate(
            @Valid @RequestBody CompleteFileUpdateRequest request) {
        log.info("Completing file update for videoId: {}, poster: {}, trailer: {}, video: {}",
                request.getVideoId(), request.isPoster(), request.isTrailer(), request.isVideo());

        try {
            Video video = videoService.completeFileUpdate(request.getVideoId(), request);

            ApiResponse<Video> response = ApiResponse.success(
                    "File update completed successfully", video);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Error completing file update for videoId: {}", request.getVideoId(), e);

            ApiResponse<Video> errorResponse = ApiResponse.error(
                    "Failed to complete file update: " + e.getMessage(),
                    HttpStatus.BAD_REQUEST.value());

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        }
    }
}
