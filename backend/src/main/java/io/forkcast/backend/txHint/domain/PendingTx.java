package io.forkcast.backend.txHint.domain;


import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "pending_tx")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class PendingTx {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "tx_hash", nullable = false, length = 66, unique = true)
  private String txHash;

  @Column(name = "action_type", nullable = false, length = 50)
  private String actionType;

  @Column(name="user_address", nullable = false, length = 42)
  private String userAddress;

  @Enumerated(EnumType.STRING)
  @Column(name="status", nullable = false, length = 30)
  private PendingTxStatus status;

  @Column(name="submitted_at", nullable = false)
  private Instant submittedAt;

  public PendingTx(String txHash, String actionType, String userAddress) {
    this.txHash = txHash;
    this.actionType = actionType;
    this.userAddress = userAddress;
    this.status = PendingTxStatus.PENDING;
    this.submittedAt = Instant.now();
  }

  public void markMinedUnconfirmed() {
    this.status = PendingTxStatus.MINED_UNCONFIRMED;
  }

  public void markConfirmed() {
    this.status = PendingTxStatus.CONFIRMED;
  }

  public void markFailed() {
    this.status = PendingTxStatus.FAILED;
  }

  public void markExpired() {
    this.status = PendingTxStatus.EXPIRED;
  }
}
