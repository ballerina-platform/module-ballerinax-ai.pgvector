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
import ballerina/io;
import ballerina/uuid;
import ballerinax/ai.pgvector;

configurable string host = ?;
configurable string user = ?;
configurable string password = ?;
configurable string database = ?;
configurable string tableName = ?;

type CustomerQuery record {
    float[] embedding;
    string query;
    string solution;
};

public function main() returns error? {
    pgvector:VectorStore vectorStore = check new (
        host,
        user,
        password,
        database,
        tableName,
        configs = {
            vectorDimension: 3
        }
    );

    CustomerQuery[] entries = [
        {
            query: "How to reset my password?",
            solution: "To reset your password, please go to the login page and click on the Forgot Password link.",
            embedding: [0.1011, 0.20012, 0.3024]
        },
        {
            query: "How to change my email address?",
            solution: "To change your email address, please go to the profile page and click on the Change Email link.",
            embedding: [0.5645, 0.574, 0.3384]
        },
        {
            query: "How to delete my account?",
            solution: "To delete your account, please go to the profile page and click on the Delete Account link.",
            embedding: [0.789, 0.890, 0.901]
        }
    ];

    ai:Error? addResult = vectorStore.add(from CustomerQuery entry in entries
        select {
            id: uuid:createRandomUuid(),
            embedding: entry.embedding,
            chunk: {
                'type: "text",
                content: entry.query,
                metadata: {
                    "solution": entry.solution
                }
            }
        }
    );
    if addResult is ai:Error {
        io:println("Error occurred while adding an entry to the vector store", addResult);
        return;
    }

    // This is the embedding of the search query. It should use the same model as the embedding of the book entries.
    ai:Vector searchEmbedding = [0.1, 0.2, 0.3];

    ai:VectorMatch[]|error query = vectorStore.query({
        embedding: searchEmbedding,
        filters: {
            filters: [
                {
                    'key: "solution",
                    operator: ai:EQUAL,
                    value: "To reset your password, please go to the login page and click on the Forgot Password link."
                }
            ]
        }
    });
    io:println("Query Results: ", query);
}

