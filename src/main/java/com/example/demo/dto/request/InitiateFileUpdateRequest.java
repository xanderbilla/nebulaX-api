package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.AssertTrue;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InitiateFileUpdateRequest {

    // Boolean flags to indicate what files to update
    private boolean includeVideo;
    private boolean includePoster;
    private boolean includeTrailer;

    // Optional: only if user wants to change the folder path during update
    private String folderPath;

    // Custom validation to ensure at least one file type is selected
    @AssertTrue(message = "At least one file type must be selected for update (includeVideo, includePoster, or includeTrailer)")
    public boolean isAtLeastOneTypeSelected() {
        return includeVideo || includePoster || includeTrailer;
    }
}
