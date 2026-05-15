package io.forkcast.backend.snapshot.service;

import io.forkcast.backend.snapshot.domain.PositionSnapshot;
import io.forkcast.backend.snapshot.repository.PositionSnapshotRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.time.Instant;
import java.time.temporal.ChronoUnit;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
  "sync.rpc.url=http://localhost:8545",
  "sync.contracts.strategy-router-address=0x0000000000000000000000000000000000000000",
  "sync.contracts.hook-address=0x0000000000000000000000000000000000000000",
  "STRATEGY_LENS_ADDRESS=0x0000000000000000000000000000000000000000"
})
class SnapshotWriteServiceTest {

  @Autowired
  private SnapshotWriteService snapshotWriteService;

  @Autowired
  private PositionSnapshotRepository positionSnapshotRepository;

  @BeforeEach
  void setUp() {
    positionSnapshotRepository.deleteAll();
  }

  @Test
  void purgeOlderThan_deletesOldAndKeepsRecent() {
    positionSnapshotRepository.save(snapshot(1L, Instant.now().minus(8, ChronoUnit.DAYS)));
    positionSnapshotRepository.save(snapshot(1L, Instant.now().minus(3, ChronoUnit.DAYS)));

    int deleted = snapshotWriteService.purgeOlderThan(7);

    assertThat(deleted).isEqualTo(1);
    assertThat(positionSnapshotRepository.count()).isEqualTo(1);
    assertThat(positionSnapshotRepository.findAll().get(0).getSnapshotAt())
      .isAfter(Instant.now().minus(7, ChronoUnit.DAYS));
  }

  @Test
  void purgeOlderThan_doesNotDeleteWhenNothingIsOld() {
    positionSnapshotRepository.save(snapshot(1L, Instant.now().minus(3, ChronoUnit.DAYS)));

    int deleted = snapshotWriteService.purgeOlderThan(7);

    assertThat(deleted).isEqualTo(0);
    assertThat(positionSnapshotRepository.count()).isEqualTo(1);
  }

  private PositionSnapshot snapshot(Long tokenId, Instant snapshotAt) {
    return new PositionSnapshot(
      tokenId,
      "0x0000000000000000000000000000000000000001",
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004",
      true,
      BigInteger.valueOf(1000L),
      BigInteger.valueOf(2000L),
      BigInteger.valueOf(3000L),
      181,
      BigInteger.valueOf(4000L),
      BigInteger.valueOf(5000L),
      BigInteger.valueOf(6000L),
      new BigDecimal("1.234567890123456789"),
      snapshotAt,
      12345L
    );
  }
}
