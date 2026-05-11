package io.forkcast.backend.snapshot.service;

import io.forkcast.backend.snapshot.domain.PositionSnapshot;
import io.forkcast.backend.snapshot.repository.PositionSnapshotRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class SnapshotWriteService {

  private final PositionSnapshotRepository positionSnapshotRepository;

  public SnapshotWriteService(PositionSnapshotRepository positionSnapshotRepository) {
    this.positionSnapshotRepository = positionSnapshotRepository;
  }

  @Transactional
  public void saveAll(List<PositionSnapshot> snapshots) {
    if (snapshots.isEmpty()) {
      return ;
    }

    positionSnapshotRepository.saveAll(snapshots);
  }
}
