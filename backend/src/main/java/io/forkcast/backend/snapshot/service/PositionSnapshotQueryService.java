package io.forkcast.backend.snapshot.service;

import io.forkcast.backend.snapshot.dto.PositionSnapshotResponse;
import io.forkcast.backend.snapshot.repository.PositionSnapshotRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(readOnly = true)
public class PositionSnapshotQueryService {

  private final PositionSnapshotRepository positionSnapshotRepository;

  public PositionSnapshotQueryService(PositionSnapshotRepository positionSnapshotRepository) {
    this.positionSnapshotRepository = positionSnapshotRepository;
  }

  public List<PositionSnapshotResponse> getSnapshots(Long tokenId, int limit) {
    return positionSnapshotRepository.findByTokenIdOrderBySnapshotAtDesc(
      tokenId,
      PageRequest.of(0, limit)
    ).stream().map(PositionSnapshotResponse::from).toList();
  }
}
