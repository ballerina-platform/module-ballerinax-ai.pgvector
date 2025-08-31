// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/log;
import ballerina/sql;
import ballerina/uuid;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

# Pgvector Vector Store implementation with support for Dense, Sparse, and Hybrid vector search modes.
#
# This class implements the ai:VectorStore interface and integrates with the Pgvector vector database
# to provide functionality for vector upsert, query, and deletion.
#
public isolated class VectorStore {
    *ai:VectorStore;
    final postgresql:Client dbClient;
    private final int vectorDimension;
    private string tableName = "vector_store";
    private final ai:VectorStoreQueryMode embeddingType;

    # Initializes the pgvector vector store with the provided configuration.
    #
    # + configs - Contains configuration for database connections and other necessary parameters
    public isolated function init(Configuration configs) returns error? {
        self.dbClient = check new (
            host = configs.host,
            username = configs.user,
            password = configs.password,
            database = configs.database,
            port = configs.port,
            options = configs.options,
            connectionPool = configs.connectionPool
        );
        self.vectorDimension = configs.vectorDimension;
        self.embeddingType = configs.embeddingType;
        string? tableName = configs.tableName;
        self.tableName = tableName !is () ? tableName : self.tableName;
        lock {
            error? initError = self.initializeDatabase(self.tableName);
            if initError is error {
                log:printError("error during database initialization.", initError);
            }
        }
    }

    # Adds vector entries to the vector store database.
    #
    # + entries - Array of vector entries to be added
    #
    # + return - Returns an `ai:Error` if the operation fails, otherwise returns nil
    public isolated function add(ai:VectorEntry[] entries) returns ai:Error? {
        lock {
            foreach ai:VectorEntry item in entries.cloneReadOnly() {
                ai:Embedding embedding = item.embedding;
                string embeddings = embedding is ai:SparseVector ?
                    serializeSparseEmbedding(embedding, self.vectorDimension) : embedding.toJsonString();
                string embeddingType = embedding is ai:SparseVector ? "sparsevec" : "vector";
                string? id = item.id;
                map<string> metadata = item.chunk.metadata !is () ? check item.chunk.metadata.cloneWithType() : {};
                metadata["type"] = item.chunk.'type;

                string query = string `
                    INSERT INTO ${sanitizeValue(self.tableName)} (
                        id,
                        embedding,
                        content,
                        metadata)
                    VALUES (
                        '${id !is () ? sanitizeValue(id) : uuid:createRandomUuid()}',
                        '${embeddings.toString()}'::${embeddingType},
                        '${sanitizeValue(item.chunk.content.toString())}',
                        '${sanitizeValue(metadata.toJsonString())}'
                    )`;
                sql:ParameterizedQuery parameterizedQuery = ``;
                parameterizedQuery.strings = [query];
                _ = check self.dbClient->execute(parameterizedQuery);
            }
            return;
        } on fail error err {
            return error("failed to add entries to the vector store", err);
        }
    }

    # Deletes vector entries from the vector store database by ID(s).
    #
    # + ids - Single ID or array of IDs to delete
    #
    # + return - Returns an `ai:Error` if the operation fails, otherwise returns nil
    public isolated function delete(string|string[] ids) returns ai:Error? {
        lock {
            string query = ids is string ?
                string `DELETE FROM ${self.tableName} WHERE id = '${sanitizeValue(ids)}'` :
                string `DELETE FROM ${self.tableName} WHERE id IN 
                    ('${sanitizeValue(string:'join("','", ...ids.cloneReadOnly()))}')`;
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [query];
            _ = check self.dbClient->execute(parameterizedQuery);
        } on fail error err {
            return error("failed to delete entry from the vector store", err);
        }
    }

    # Queries the vector store for matches to the given query embedding and filters.
    #
    # + query - The vector store query containing embedding and optional filters
    #
    # + return - Returns an array of `ai:VectorMatch` results or an `ai:Error` if the operation fails
    public isolated function query(ai:VectorStoreQuery query) returns ai:VectorMatch[]|ai:Error {
        ai:VectorMatch[] finalMatches = [];
        lock {
            if query.topK == 0 {
                return error("Invalid value for topK. The value cannot be 0.");
            }
            ai:VectorMatch[] matches = [];
            ai:Embedding? embedding = query.cloneReadOnly().embedding;
            ai:MetadataFilters? filters = query.cloneReadOnly().filters;
            string queryValue = "";
            if embedding is () && filters is () {
                queryValue = string `
                        SELECT
                            id::text AS id,
                            embedding::text AS embedding,
                            content::text AS content,
                            metadata::json AS metadata
                        FROM ${sanitizeValue(self.tableName)}
                        ${query.topK > -1 ? string `LIMIT ${query.topK}` : ""};
                    `;
            } else if embedding is () && filters !is () {
                string filterQuery = generateFilter(filters);
                queryValue = string `
                    SELECT
                        id::text AS id,
                        embedding::text AS embedding,
                        content::text AS content,
                        metadata::json AS metadata
                    FROM ${sanitizeValue(self.tableName)}
                    WHERE ${sanitizeValue(filterQuery)}
                    ${query.topK > -1 ? string `LIMIT ${query.topK}` : ""};
                `;
            } else {
                string embeddings = embedding is ai:SparseVector ?
                    serializeSparseEmbedding(embedding, self.vectorDimension) : embedding.toJsonString();
                string embeddingType = embedding is ai:SparseVector ? "sparsevec" : "vector";
                string filterQuery = filters !is () ? generateFilter(filters) : "";
                string baseWhereClause = string `similarity IS NOT NULL AND NOT similarity = 'NaN'::float`;
                string innerFilterClause = filterQuery != "" ? string `AND ${filterQuery}` : "";
                queryValue = string `
                    ${embedding is ai:SparseVector ?
                        string `
                            SELECT *
                            FROM (
                                SELECT
                                    id::text AS id,
                                    embedding::text AS embedding,
                                    content::text AS content,
                                    metadata::json AS metadata,
                                    (1 - (embedding <=> '${embeddings}'::${embeddingType})) AS similarity
                                FROM ${sanitizeValue(self.tableName)}
                                ${sanitizeValue(innerFilterClause)}
                            ) t
                            WHERE ${baseWhereClause}
                            ORDER BY similarity DESC
                            LIMIT ${query.topK};` :
                        string `
                            SELECT
                                id::text AS id,
                                embedding::text AS embedding,
                                content::text AS content,
                                metadata::json AS metadata,
                                (1 - (embedding <=> '${embeddings}'::${embeddingType})) AS similarity
                            FROM ${sanitizeValue(self.tableName)}
                            WHERE
                                (1 - (embedding <=> '${embeddings}'::vector)) IS NOT NULL AND NOT
                                ((1 - (embedding <=> '${embeddings}'::vector)) = 'NaN'::float)
                                ${sanitizeValue(innerFilterClause)}
                            ORDER BY similarity DESC
                            LIMIT ${query.topK};`
                    }`;
            }
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [queryValue];
            stream<SearchResult, sql:Error?> resultStream = self.dbClient->query(parameterizedQuery);
            record {|SearchResult value;|}? result = check resultStream.next();
            while result !is () {
                Metadata? metadata = result.value?.metadata !is () ? check result.value?.metadata.cloneWithType(Metadata) : {};
                ai:Embedding parsedEmbedding = self.embeddingType == ai:SPARSE
                    ? check deserializeSparseEmbedding(result.value.embedding, self.vectorDimension.cloneReadOnly())
                    : check result.value.embedding.fromJsonStringWithType();
                matches.push({
                    id: result.value.id,
                    embedding: parsedEmbedding,
                    chunk: {
                        'type: metadata !is () && metadata.'type !is () ? <string>metadata.'type : "",
                        content: result.value.content is () ? result.value.content : "",
                        metadata: metadata !is () ? check metadata.cloneWithType() : ()
                    },
                    similarityScore: result.value.similarity is float ?
                        check result.value.similarity.cloneWithType() : 0.0
                });
                result = check resultStream.next();
            }
            finalMatches = matches.cloneReadOnly();
        } on fail var err {
            return error("failed to query the vector store", err);
        }
        return finalMatches;
    }

    isolated function initializeDatabase(string tableName) returns error? {
        _ = check self.dbClient->execute(`CREATE EXTENSION IF NOT EXISTS vector`);

        sql:ParameterizedQuery parameterizedQuery = ``;
        string query = string `
            CREATE TABLE IF NOT EXISTS ${sanitizeValue(tableName)} (
                id VARCHAR PRIMARY KEY,
                content TEXT,
                embedding ${self.embeddingType == ai:SPARSE ? "sparsevec" : "vector"}(${self.vectorDimension}),
                metadata JSONB
            )`;
        parameterizedQuery.strings = [query];
        _ = check self.dbClient->execute(parameterizedQuery);

        string opClass = self.embeddingType == ai:SPARSE ? "sparsevec_cosine_ops" : "vector_cosine_ops";
        query = string `
            CREATE INDEX IF NOT EXISTS ${sanitizeValue(tableName)}_embedding_idx
            ON ${sanitizeValue(tableName)}
            USING hnsw (embedding ${opClass});
        `;
        parameterizedQuery.strings = [query];
        _ = check self.dbClient->execute(parameterizedQuery);
    }
}
