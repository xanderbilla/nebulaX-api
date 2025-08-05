package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.AssertTrue;

/**
 * Request DTO for completing video upload process after files are uploaded to S3.
 * Confirms which files were successfully uploaded and updates video metadata accordingly.
 * Validates that at least one file type (poster, trailer, video) was uploaded.
 * 
 * @author Xander Billa
 * @since August 3, 2025
 * @see com.example.demo.service.VideoService#completeUpload(CompleteUploadRequest)
 * @see com.example.demo.dto.request.InitiateUploadRequest
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CompleteUploadRequest {

    @NotBlank(message = "Video ID cannot be blank")
    private String videoId;

    // Boolean flags to indicate which files were uploaded
    private boolean poster;
    private boolean trailer;
    private boolean video;

    // Custom validation to ensure at least one file type was uploaded
    @AssertTrue(message = "At least one file type must be completed (poster, trailer, or video)")
    public boolean isAtLeastOneFileCompleted() {
        return poster || trailer || video;
    }
}
