package com.example.demo.dto.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Response DTO for detailed video information with process tracking.
 * Provides structured job information in a process array format.
 * 
 * @author Xander Billa
 * @since August 11, 2025
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class VideoDetailResponse {
    
    private String videoId;
    private String title;
    private String category;
    private String folderPath;
    private String createdAt;
    private String modifiedAt;
    private String s3Key;
    private String posterUrl;
    private String trailerUrl;
    private String videoUrl;
    private List<ProcessInfo> process;
    
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ProcessInfo {
        private String mediaType;
        private String jobId;
        private String jobStatus;
    }
}
