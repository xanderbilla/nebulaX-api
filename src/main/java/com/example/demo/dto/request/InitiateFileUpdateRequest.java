package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.AssertTrue;

/**
 * Request DTO for initiating file update process for existing videos.
 * Generates presigned URLs for updating specific files (poster, trailer, video) of existing videos.
 * Allows selective file updates and optional folder path changes.
 * 
 * @author Xander Billa
 * @since August 5, 2025
 * @see com.example.demo.service.VideoService#initiateFileUpdate(String, InitiateFileUpdateRequest)
 * @see com.example.demo.dto.request.CompleteFileUpdateRequest
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InitiateFileUpdateRequest {

    @NotBlank(message = "Video ID cannot be blank")
    private String videoId;

    // Boolean flags to indicate which presigned URLs to generate for update
    private boolean posterUrl;
    private boolean trailerUrl;
    private boolean videoUrl;

    // Optional: only if user wants to change the folder path during update
    private String folderPath;

    // Custom validation to ensure at least one URL type is requested
    @AssertTrue(message = "At least one URL type must be selected for update (posterUrl, trailerUrl, or videoUrl)")
    public boolean isAtLeastOneUrlSelected() {
        return posterUrl || trailerUrl || videoUrl;
    }
}
