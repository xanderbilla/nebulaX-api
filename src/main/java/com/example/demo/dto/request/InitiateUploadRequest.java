package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.AssertTrue;

/**
 * Request DTO for initiating video upload process with automatic videoId generation.
 * Contains metadata and file type selection for generating presigned S3 URLs.
 * Supports selective file upload (poster, trailer, video) based on boolean flags.
 * 
 * @author Xander Billa
 * @since August 4, 2025
 * @see com.example.demo.service.VideoService#initiateUpload(InitiateUploadRequest)
 * @see com.example.demo.dto.response.InitiateUploadResponse
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InitiateUploadRequest {

    @NotBlank(message = "Title cannot be blank")
    @Size(min = 1, max = 255, message = "Title must be between 1 and 255 characters")
    private String title;

    @NotBlank(message = "Category cannot be blank")
    @Pattern(regexp = "^(tv|movie|live)$", message = "Category must be one of: tv, movie, live")
    private String category;

    @NotBlank(message = "Folder path cannot be blank")
    private String folderPath;

    // Boolean flags to indicate which presigned URLs to generate
    private boolean posterUrl;
    private boolean trailerUrl;
    private boolean videoUrl;

    // Custom validation to ensure at least one URL type is requested
    @AssertTrue(message = "At least one URL type must be selected (posterUrl, trailerUrl, or videoUrl)")
    public boolean isAtLeastOneUrlSelected() {
        return posterUrl || trailerUrl || videoUrl;
    }
}
