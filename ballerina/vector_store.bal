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
    private int topK;

    public isolated function init(Configuration configs, int vectorDimension = 1536) returns error? {

        self.dbClient = check new (
            host = configs.host,
            username = configs.user,
            password = configs.password,
            database = configs.database,
            port = configs.port,
            options = configs.options,
            connectionPool = configs.connectionPool
        );
        self.vectorDimension = vectorDimension;
        self.embeddingType = configs.embeddingType;
        string? tableName = configs.tableName;
        self.tableName = tableName !is () ? tableName : self.tableName;

        self.topK = configs.topK;
        lock {
            error? initError = self.initializeDatabase(self.tableName);
            if initError is error {
                log:printError("error during database initialization.", initError);
            }
        }
    }

    private isolated function initializeDatabase(string tableName) returns error? {
        _ = check self.dbClient->execute(`CREATE EXTENSION IF NOT EXISTS vector`);

        sql:ParameterizedQuery parameterizedQuery = ``;
        string query = string `CREATE TABLE IF NOT EXISTS ${tableName} (
            id VARCHAR PRIMARY KEY,
            content TEXT,
            embedding ${self.embeddingType == ai:SPARSE ? "sparsevec" : "vector"}(${self.vectorDimension}),
            metadata JSONB
        )`;
        parameterizedQuery.strings = [query];
        _ = check self.dbClient->execute(parameterizedQuery);

        string opClass = self.embeddingType == ai:SPARSE ? "sparsevec_cosine_ops" : "vector_cosine_ops";
        query = string `
            CREATE INDEX IF NOT EXISTS ${tableName}_embedding_idx
            ON ${tableName}
            USING hnsw (embedding ${opClass});
        `;
        parameterizedQuery.strings = [query];
        _ = check self.dbClient->execute(parameterizedQuery);
    }

    public isolated function add(ai:VectorEntry[] entries) returns ai:Error? {
        lock {
            foreach ai:VectorEntry item in entries.cloneReadOnly() {
                ai:Embedding embedding = item.embedding;
                string embeddings = embedding is ai:SparseVector ?
                    serializeSparseEmbedding(embedding, self.vectorDimension) : embedding.toJsonString();
                string embeddingType = embedding is ai:SparseVector ? "sparsevec" : "vector";
                string? id = item.id;
                string query = string `INSERT INTO ${self.tableName} (
                    id,
                    embedding, 
                    content) 
                VALUES (
                    '${id !is () ? id : uuid:createRandomUuid()}',
                    '${embeddings.toString()}'::${embeddingType},
                    '${item.chunk.content.toString()}'
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

    public isolated function delete(string id) returns ai:Error? {
        lock {
            string query = string `DELETE FROM ${self.tableName} WHERE id = '${id}'`;
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [query];
            _ = check self.dbClient->execute(parameterizedQuery);
            return;
        } on fail error err {
            return error("failed to delete entry from the vector store", err);
        }
    }

    public isolated function query(ai:VectorStoreQuery query) returns ai:VectorMatch[]|ai:Error {
        ai:VectorMatch[] finalMatches = [];
        lock {
            ai:Embedding embedding = query.cloneReadOnly().embedding;
            string embeddings = embedding is ai:SparseVector ?
                serializeSparseEmbedding(embedding, self.vectorDimension) : embedding.toJsonString();
            string embeddingType = embedding is ai:SparseVector ? "sparsevec" : "vector";
            ai:VectorMatch[] matches = [];
            ai:MetadataFilters? filters = query.cloneReadOnly().filters;
            string filterQuery = filters !is () ? generateFilter(filters) : "";
            string baseWhereClause = string `similarity IS NOT NULL AND NOT similarity = 'NaN'::float`;
            string innerFilterClause = filterQuery != "" ? string `AND ${filterQuery}` : "";
            string queryValue = string `
                ${embedding is ai:SparseVector ? 
                    string `SELECT *
                        FROM (
                            SELECT 
                                id::text AS id,
                                embedding::text AS embedding,
                                metadata::text AS metadata,
                                (1 - (embedding <=> '${embeddings}'::${embeddingType})) AS similarity
                            FROM ${self.tableName}
                            ${innerFilterClause}
                        ) t
                        WHERE ${baseWhereClause}
                        ORDER BY similarity DESC
                        LIMIT ${self.topK};` : 
                    string `SELECT 
                            id::text AS id,
                            embedding::text AS embedding,
                            metadata::text AS metadata,
                            (1 - (embedding <=> '${embeddings}'::${embeddingType})) AS similarity
                        FROM ${self.tableName}
                        WHERE 
                            (1 - (embedding <=> '${embeddings}'::vector)) IS NOT NULL AND NOT 
                            ((1 - (embedding <=> '${embeddings}'::vector)) = 'NaN'::float) 
                            ${innerFilterClause}
                        ORDER BY similarity DESC
                        LIMIT ${self.topK};`
            }`;
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [queryValue];
            stream<SearchResult, sql:Error?> resultStream = self.dbClient->query(parameterizedQuery);
            record {|SearchResult value;|}? result = check resultStream.next();
            while result !is () {
                string? metadata = result.value.metadata;
                ai:Embedding parsedEmbedding = self.embeddingType == ai:SPARSE
                    ? check deserializeSparseEmbedding(result.value.embedding, self.vectorDimension.cloneReadOnly())
                    : check result.value.embedding.fromJsonStringWithType();
                map<string> metadataMap = metadata !is () ? check metadata.fromJsonStringWithType() : {};
                matches.push({
                    id: result.value.id,
                    embedding: parsedEmbedding,
                    chunk: {
                        'type: metadataMap.hasKey("type") ? metadataMap.get("type") : "",
                        content: metadataMap.hasKey("content") ? metadataMap.get("content") : ""
                    },
                    similarityScore: result.value.similarity is float ? check result.value.similarity.cloneWithType() : 0.0
                });
                result = check resultStream.next();
            }
            finalMatches = matches.cloneReadOnly();
        } on fail var err {
            return error("failed to query the vector store", err);
        }
        return finalMatches;
    }
}
