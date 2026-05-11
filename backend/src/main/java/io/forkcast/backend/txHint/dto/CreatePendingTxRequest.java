package io.forkcast.backend.txHint.dto;


import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CreatePendingTxRequest {

  @NotBlank
  private String txHash;

  @NotBlank
  private String actionType;

  @NotBlank
  private String userAddress;


}
