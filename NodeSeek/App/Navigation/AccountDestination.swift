import NodeSeekCore

enum AccountDestination: Hashable {
    case content(AccountContentKind)
    case ledger(LedgerKind)
    case stardustHistory
    case attendance
    case progress
    case profile
    case settings
}
