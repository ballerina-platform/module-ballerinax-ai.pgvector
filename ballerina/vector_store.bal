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
    private string tableName;
    private final ai:VectorStoreQueryMode embeddingType;
    private final SimilarityMetric similarityMetric;

    # Initializes the pgvector vector store with the provided configuration.
    #
    # + configs - Contains configuration for database connections and other necessary parameters
    public isolated function init(string host, string user, string password, string database,
            string tableName = "vector_store", int port = 5432, postgresql:Options options = {},
            sql:ConnectionPool connectionPool = {}, Configuration configs = {}) returns ai:Error? {
        do {
            self.dbClient = check new (host, user, password, database, port, options, connectionPool);
            self.vectorDimension = configs.vectorDimension;
            self.embeddingType = configs.embeddingType;
            self.tableName = tableName;
            self.similarityMetric = configs.similarityMetric;
            lock {
                check self.initializeDatabase(self.tableName);
            }
        } on fail error err {
            return error("failed to initialize the vector store", err);
        }
    }

    # Adds vector entries to the vector store database.
    #
    # + entries - Array of vector entries to be added
    #
    # + return - Returns an `ai:Error` if the operation fails, otherwise returns nil
    public isolated function add(ai:VectorEntry[] entries) returns ai:Error? {
        lock {
            if entries.length() == 0 {
                return;
            }
            string[] valuesClauses = [];
            foreach ai:VectorEntry item in entries.cloneReadOnly() {
                ai:Embedding embedding = item.embedding;
                string embeddings = embedding is ai:SparseVector ?
                    serializeSparseEmbedding(embedding, self.vectorDimension) : embedding.toJsonString();
                string embeddingType = embedding is ai:SparseVector ? "sparsevec" : "vector";
                string? id = item.id;
                map<string> metadata = item.chunk.metadata !is () ? check item.chunk.metadata.cloneWithType() : {};
                metadata["type"] = item.chunk.'type;

                string valuesClause = string `(
                    '${id !is () ? sanitizeValue(id) : uuid:createRandomUuid()}',
                    '${embeddings.toString()}'::${embeddingType},
                    '${sanitizeValue(item.chunk.content.toString())}',
                    '${sanitizeValue(metadata.toJsonString())}'
                )`;
                valuesClauses.push(valuesClause);
            }
            string query = string `
                INSERT INTO ${sanitizeValue(self.tableName)} (
                    id,
                    embedding,
                    content,
                    metadata)
                VALUES ${string:'join(", ", ...valuesClauses)}`;
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [query];
            _ = check self.dbClient->execute(parameterizedQuery);
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
                                    (1 - (embedding ${self.similarityMetric} '${embeddings}'::${embeddingType})) AS similarity
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
                                (1 - (embedding ${self.similarityMetric} '${embeddings}'::${embeddingType})) AS similarity
                            FROM ${sanitizeValue(self.tableName)}
                            WHERE
                                (1 - (embedding ${self.similarityMetric} '${embeddings}'::vector)) IS NOT NULL AND NOT
                                ((1 - (embedding ${self.similarityMetric} '${embeddings}'::vector)) = 'NaN'::float)
                                ${sanitizeValue(innerFilterClause)}
                            ORDER BY similarity DESC
                            LIMIT ${query.topK};`
                    }`;
            }
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [queryValue];
            stream<SearchResult, sql:Error?> resultStream = self.dbClient->query(parameterizedQuery);
            check from SearchResult item in resultStream
                do {
                    json? metaJson = item["metadata"];
                    Metadata? metadata = metaJson is () ? () : check metaJson.cloneWithType(Metadata);
                    ai:Embedding parsedEmbedding = self.embeddingType == ai:SPARSE
                        ? check deserializeSparseEmbedding(item.embedding, self.vectorDimension.cloneReadOnly())
                        : check item.embedding.fromJsonStringWithType();
                    matches.push({
                        id: item.id,
                        embedding: parsedEmbedding,
                        chunk: {
                            'type: metadata !is () && metadata["type"] is string ? <string>metadata["type"] : "",
                            content: item["content"] is string ? <string>item["content"] : "",
                            metadata: metadata !is () ? check metadata.cloneWithType() : ()
                        },
                        similarityScore: item["similarity"] is float ?
                            <float>item["similarity"] : 0.0
                    });
                };
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
