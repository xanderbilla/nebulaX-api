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
public class CompleteFileUpdateRequest {

    private boolean poster;
    private boolean trailer;

    @AssertTrue(message = "At least one of poster or trailer must be true")
    public boolean isValid() {
        return poster || trailer;
    }
}
