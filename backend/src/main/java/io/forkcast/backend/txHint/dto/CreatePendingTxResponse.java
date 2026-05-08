package io.forkcast.backend.txHint.dto;


import io.forkcast.backend.txHint.domain.PendingTx;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
public class CreatePendingTxResponse {

  private final String status;
  private final String txHash;

  public CreatePendingTxResponse(String status, String txHash) {
    this.status = status;
    this.txHash = txHash;
  }

  public static CreatePendingTxResponse from(PendingTx pendingTx) {
    return new CreatePendingTxResponse(
      "ACCEPTED",
      pendingTx.getTxHash()
    );
  }

}
