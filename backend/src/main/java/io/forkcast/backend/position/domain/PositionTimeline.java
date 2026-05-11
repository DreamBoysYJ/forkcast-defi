package io.forkcast.backend.position.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.ColumnTransformer;

import java.time.Instant;

@Entity
@Table(name = "position_timeline")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class PositionTimeline {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "token_id", nullable = false)
  private Long tokenId;

  @Column(name = "event_type", nullable = false, length = 50)
  private String eventType;

  @Column(name = "tx_hash", nullable = false, length = 66)
  private String txHash;

  @Column(name = "block_number", nullable = false)
  private long blockNumber;

  @Column(name = "event_timestamp", nullable = false)
  private Instant eventTimestamp;

  @Column(name = "user_address", nullable = false, length = 42)
  private String userAddress;

  @Column(name = "vault_address", nullable = false, length = 42)
  private String vaultAddress;

  @Column(name = "metadata_json", nullable = false, columnDefinition = "jsonb")
  @ColumnTransformer(write = "?::jsonb")
  private String metadataJson;

  public PositionTimeline(
    Long tokenId,
    String eventType,
    String txHash,
    long blockNumber,
    Instant eventTimestamp,
    String userAddress,
    String vaultAddress,
    String metadataJson
  ) {
    this.tokenId = tokenId;
    this.eventType = eventType;
    this.txHash = txHash;
    this.blockNumber = blockNumber;
    this.eventTimestamp = eventTimestamp;
    this.userAddress = userAddress;
    this.vaultAddress = vaultAddress;
    this.metadataJson = metadataJson;
  }
}
