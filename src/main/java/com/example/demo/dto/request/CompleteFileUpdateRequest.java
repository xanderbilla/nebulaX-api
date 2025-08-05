package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.AssertTrue;

/**
 * Request DTO for completing file update process after new files are uploaded to S3.
 * Confirms which files were successfully updated and finalizes the video metadata.
 * Requires at least one file type to be updated for the operation to be valid.
 * 
 * @author Xander Billa
 * @since August 4, 2025
 * @see com.example.demo.service.VideoService#completeFileUpdate(String, CompleteFileUpdateRequest)
 * @see com.example.demo.dto.request.InitiateFileUpdateRequest
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CompleteFileUpdateRequest {

    @NotBlank(message = "Video ID cannot be blank")
    private String videoId;

    private boolean poster;
    private boolean trailer;
    private boolean video;

    @AssertTrue(message = "At least one file type must be completed (poster, trailer, or video)")
    public boolean isAtLeastOneFileCompleted() {
        return poster || trailer || video;
    }
}
