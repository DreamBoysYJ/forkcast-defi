package io.forkcast.backend.snapshot.repository;

import io.forkcast.backend.snapshot.domain.PositionSnapshot;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface PositionSnapshotRepository extends JpaRepository<PositionSnapshot, Long> {
  boolean existsByTokenIdAndSnapshotAt(Long tokenId, Instant snapshotAt);

  List<PositionSnapshot> findByTokenIdOrderBySnapshotAtDesc(Long tokenId, Pageable pageable);

  @Modifying(clearAutomatically = true)
  @Query("DELETE FROM PositionSnapshot p WHERE p.snapshotAt < :cutoff")
  int deleteBySnapshotAtBefore(@Param("cutoff") Instant cutoff);
}
