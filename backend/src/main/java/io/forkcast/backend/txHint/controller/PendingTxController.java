package io.forkcast.backend.txHint.controller;


import io.forkcast.backend.txHint.domain.PendingTx;
import io.forkcast.backend.txHint.dto.CreatePendingTxRequest;
import io.forkcast.backend.txHint.dto.CreatePendingTxResponse;
import io.forkcast.backend.txHint.service.PendingTxService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/tx-hints")
public class PendingTxController {

  private final PendingTxService pendingTxService;

  public PendingTxController(PendingTxService pendingTxService) {
    this.pendingTxService = pendingTxService;
  }

  @PostMapping
  @ResponseStatus(HttpStatus.ACCEPTED)
  public CreatePendingTxResponse create(@Valid @RequestBody CreatePendingTxRequest request) {
    PendingTx pendingTx = pendingTxService.create(
      request.getTxHash(), request.getActionType(), request.getUserAddress()
    );

    return CreatePendingTxResponse.from(pendingTx);
  }
}
