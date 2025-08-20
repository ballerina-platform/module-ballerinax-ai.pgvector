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
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/log;
import ballerina/uuid;

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
    private Column[] additionalColumns = [];
    private int topK;

    public isolated function init(ConnectionConfig connectionConfigs, int vectorDimension = 1536, postgresql:Options options = {
                connectTimeout: 10,
                ssl: {
                    mode: postgresql:REQUIRE
                }
            }, sql:ConnectionPool connectionPool = {}) returns error? {

        self.dbClient = check new (
            host = connectionConfigs.host,
            username = connectionConfigs.user,
            password = connectionConfigs.password,
            database = connectionConfigs.database,
            port = connectionConfigs.port,
            options = options,
            connectionPool = connectionPool
        );
        self.vectorDimension = vectorDimension;

        string? tableName = connectionConfigs.tableName;
        self.tableName = tableName !is () ? tableName : self.tableName;

        Column[]? additionalColumns = connectionConfigs.additionalColumns;
        self.additionalColumns = additionalColumns !is () ? additionalColumns.cloneReadOnly() : self.additionalColumns.cloneReadOnly();
        self.topK = connectionConfigs.topK;
        lock {
            error? initError = self.initializeDatabase(self.tableName, self.additionalColumns);
            if initError is error {
                log:printWarn("Error during the initializing database.", initError);
            }
        }
    }

    private isolated function initializeDatabase(string tableName, Column[] additionalColumns) returns error? {
        _ = check self.dbClient->execute(`CREATE EXTENSION IF NOT EXISTS vector`);
        string newColumns = generateColumns(additionalColumns);
        sql:ParameterizedQuery parameterizedQuery = ``;
        string query = string `CREATE TABLE IF NOT EXISTS ${tableName} (
            id VARCHAR PRIMARY KEY,
            embedding vector(${self.vectorDimension}),
            metadata JSONB ${newColumns != "" ? ", " + newColumns : ""}
        )`;
        parameterizedQuery.strings = [query];
        _ = check self.dbClient->execute(parameterizedQuery);

        query = string `
            CREATE INDEX IF NOT EXISTS ${tableName}_embedding_idx
            ON ${tableName}
            USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 100);
        `;
        parameterizedQuery.strings = [query];
        _ = check self.dbClient->execute(parameterizedQuery);
    }

    public isolated function add(ai:VectorEntry[] entries) returns ai:Error? {
        lock {
            foreach ai:VectorEntry item in entries.cloneReadOnly() {
                string? id = item.id;
                string query = string `INSERT INTO ${self.tableName} (
                    id,
                    embedding, 
                    metadata) 
                VALUES (
                    '${id !is () ? id : uuid:createRandomUuid()}',
                    '${item.embedding.toJsonString()}'::vector,
                    '${item.chunk.toJsonString()}'::jsonb
                )
                RETURNING embedding, metadata`;
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
            ai:VectorMatch[] matches = [];
            string embeddingJson = query.embedding.toJsonString();
            ai:MetadataFilters? filters = query.cloneReadOnly().filters;
            string filterQuery = "";
            if filters !is () {
                filterQuery = generateFilter(filters);
            }
            string baseWhereClause = 
                string `(1 - (embedding <=> '${embeddingJson}'::vector)) 
                    IS NOT NULL AND NOT ((1 - (embedding <=> '${embeddingJson}'::vector)) = 'NaN'::float)`;
            string fullWhereClause = filterQuery != "" 
                ? string `${baseWhereClause} AND ${filterQuery}` : baseWhereClause;

            string queryValue = string `
                SELECT 
                    id::text AS id,
                    embedding::text AS embedding,
                    metadata::text AS metadata,
                    (1 - (embedding <=> '${embeddingJson}'::vector)) AS similarity
                FROM ${self.tableName}
                WHERE ${fullWhereClause}
                ORDER BY similarity DESC
                LIMIT ${self.topK};
            `;
            sql:ParameterizedQuery parameterizedQuery = ``;
            parameterizedQuery.strings = [queryValue];
            stream<SearchResult, sql:Error?> resultStream = self.dbClient->query(parameterizedQuery);

            record {|SearchResult value;|}? result = check resultStream.next();
            while result !is () {
                string? metadata = result.value.metadata;
                map<string> metadataMap = metadata !is () ? check metadata.fromJsonStringWithType() : {};
                matches.push({
                    id: result.value.id,
                    embedding: check result.value.embedding.fromJsonStringWithType(),
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
