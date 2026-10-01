/// Loon is a reactive collection data store for Flutter, with data dependencies and persistence.
///
/// This library is the package's public API. Everything under `src/` is internal.
library;

export 'src/json.dart';
export 'src/loon.dart'
    show
        BroadcastEvents,
        Collection,
        DependenciesBuilder,
        Document,
        DocumentChangeSnapshot,
        DocumentSnapshot,
        DocumentTypeMismatchException,
        FilterFn,
        FromJson,
        Logger,
        Loon,
        MissingSerializerEvents,
        MissingSerializerException,
        ModifyFn,
        ObservableDocument,
        ObservableQuery,
        Optional,
        PathPersistorSettings,
        Persistor,
        PersistorBuilderKey,
        PersistorKey,
        PersistorKeyBuilder,
        PersistorSettings,
        PersistorValueKey,
        Query,
        Queryable,
        SortFn,
        StoreReference,
        ToJson,
        TransactionWriter;
export 'src/persistor/data_store_encrypter.dart' show DataStoreEncrypter;
export 'src/persistor/index.dart'
    show FilePersistor, IndexedDBPersistor, SqlitePersistor;
export 'src/utils/id.dart' show generateFastId, generateSecureId;
export 'src/widgets/document_stream_builder.dart';
export 'src/widgets/query_stream_builder.dart';
