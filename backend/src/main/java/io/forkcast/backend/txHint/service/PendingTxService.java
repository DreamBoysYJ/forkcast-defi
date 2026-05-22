package io.forkcast.backend.txHint.service;


import io.forkcast.backend.txHint.domain.PendingTx;
import io.forkcast.backend.txHint.repository.PendingTxRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class PendingTxService {

  private final PendingTxRepository pendingTxRepository;

  public PendingTxService(PendingTxRepository pendingTxRepository) {
    this.pendingTxRepository = pendingTxRepository;
  }

  public PendingTx create(String txHash, String actionType, String userAddress) {
    PendingTx pendingTx = new PendingTx(txHash, actionType, userAddress);
    return pendingTxRepository.save(pendingTx);
  }

  @Transactional(readOnly = true)
  public PendingTx getByTxHashOrThrow(String txHash) {
    return pendingTxRepository.findByTxHash(txHash)
      .orElseThrow(() -> new IllegalArgumentException("Pending tx not found : " + txHash));
  }

  public PendingTx markMinedUnconfirmed(String txHash) {
    PendingTx pendingTx = getByTxHashOrThrow(txHash);
    pendingTx.markMinedUnconfirmed();
    return pendingTx;
  }

  public PendingTx markConfirmed(String txHash) {
    PendingTx pendingTx = getByTxHashOrThrow(txHash);
    pendingTx.markConfirmed();
    return pendingTx;
  }

  public PendingTx markFailed(String txHash) {
    PendingTx pendingTx = getByTxHashOrThrow(txHash);
    pendingTx.markFailed();
    return pendingTx;
  }

  public PendingTx markExpired(String txHash) {
    PendingTx pendingTx = getByTxHashOrThrow(txHash);
    pendingTx.markExpired();
    return pendingTx;
  }


}
