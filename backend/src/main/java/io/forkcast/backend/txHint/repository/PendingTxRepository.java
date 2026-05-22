package io.forkcast.backend.txHint.repository;

import io.forkcast.backend.txHint.domain.PendingTx;
import io.forkcast.backend.txHint.domain.PendingTxStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PendingTxRepository extends JpaRepository<PendingTx, Long> {

  Optional<PendingTx> findByTxHash(String txHash);

  List<PendingTx> findTop20ByUserAddressOrderBySubmittedAtDesc(String userAddress);

  List<PendingTx> findTop20ByStatusOrderBySubmittedAtDesc(PendingTxStatus status);
}
