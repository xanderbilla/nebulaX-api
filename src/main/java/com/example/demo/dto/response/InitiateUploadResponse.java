package com.example.demo.dto.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Map;

/**
 * Response DTO for upload initiation containing presigned URLs and metadata.
 * Provides auto-generated videoId and presigned S3 URLs for file uploads.
 * Contains folder structure information and S3 key details for client-side upload.
 * 
 * @author Xander Billa
 * @since August 3, 2025
 * @see com.example.demo.dto.request.InitiateUploadRequest
 * @see com.example.demo.service.VideoService#initiateUpload(com.example.demo.dto.request.InitiateUploadRequest)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InitiateUploadResponse {

    private String videoId;
    private Map<String, String> uploadUrls;
    private String s3Key;
    private String folderPath;
}
