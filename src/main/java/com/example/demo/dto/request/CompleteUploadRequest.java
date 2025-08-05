package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CompleteUploadRequest {

    @NotBlank(message = "Video ID cannot be blank")
    private String videoId;

    @NotBlank(message = "Title cannot be blank")
    @Size(min = 1, max = 255, message = "Title must be between 1 and 255 characters")
    private String title;

    @NotBlank(message = "Category cannot be blank")
    @Pattern(regexp = "^(tv|movie|live)$", message = "Category must be one of: tv, movie, live")
    private String category;

    @NotBlank(message = "Folder path cannot be blank")
    private String folderPath;

    private boolean poster;
    private boolean trailer;
}
