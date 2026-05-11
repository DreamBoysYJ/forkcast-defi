package io.forkcast.backend.txHint.domain;

public enum PendingTxStatus

{
  PENDING,
  MINED_UNCONFIRMED,
  CONFIRMED,
  FAILED,
  EXPIRED
}
