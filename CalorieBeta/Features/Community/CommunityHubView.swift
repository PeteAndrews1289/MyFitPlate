import SwiftUI
import FirebaseAuth
import Combine

struct CommunityHubView: View {
    @EnvironmentObject var groupService: GroupService
    @State private var posts: [CommunityPost] = []
    @State private var showingCreatePostView = false
    @State private var showingJoinConfirmation = false
    @State private var selectedGroup: CommunityGroup?
    @State private var groups: [CommunityGroup] = []
    @State private var isMemberOfSelectedGroup = false
    @State private var cancellables = Set<AnyCancellable>()
    
    let presetGroups = [
        CommunityGroup(id: "1", name: "Health & Wellness", description: "Discuss health tips and wellness strategies", creatorID: "preset", isPreset: true),
        CommunityGroup(id: "2", name: "Recipes & Cooking", description: "Share your favorite recipes and cooking tips", creatorID: "preset", isPreset: true),
        CommunityGroup(id: "3", name: "Fitness", description: "Talk about workouts, fitness goals, and more", creatorID: "preset", isPreset: true)
    ]
    
    var body: some View {
        NavigationView {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Groups")
                        .font(.headline)
                        .padding([.top, .leading])
                    List(presetGroups) { group in
                        Button(action: {
                            selectedGroup = group
                            if let groupID = group.id {
                                checkGroupMembership(groupID: groupID)
                            }
                        }) {
                            Text(group.name)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                    }
                    .listStyle(PlainListStyle())
                    .frame(width: UIScreen.main.bounds.width * 0.2)
                    .background(Color(.systemGray6))
                }

                Divider()
                
                VStack {
                    if let group = selectedGroup, let groupID = group.id {
                        Text("Viewing posts in \(group.name)")
                            .font(.title2)
                            .padding()
                        
                        if isMemberOfSelectedGroup {
                            Button(action: { showingCreatePostView = true }) {
                                Text("Create Post")
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding()
                            .sheet(isPresented: $showingCreatePostView) {
                                CreatePostView(groupID: groupID) { newPost in
                                    savePostToFirebase(post: newPost)
                                }
                            }
                            
                            List(posts) { post in
                                PostRowView(post: post) // Assumes PostRowView is defined elsewhere
                                    .padding(.vertical, 4)
                            }
                        } else {
                            Button("Join \(group.name) Group") {
                                showingJoinConfirmation = true
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .alert(isPresented: $showingJoinConfirmation) {
                                Alert(
                                    title: Text("Join Group"),
                                    message: Text("Would you like to join \(group.name)?"),
                                    primaryButton: .default(Text("Join")) {
                                        joinGroup(groupID: groupID)
                                    },
                                    secondaryButton: .cancel()
                                )
                            }
                        }
                    } else {
                        Text("Select a group to view posts")
                            .font(.title2)
                            .padding()
                    }
                }
            }
        }
    }

    private func checkGroupMembership(groupID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                let isMember = try await DIContainer.shared.groupRepository.checkGroupMembership(userID: userID, groupID: groupID)
                await MainActor.run {
                    self.isMemberOfSelectedGroup = isMember
                    if isMember {
                        self.fetchPostsForGroup(groupID: groupID)
                    } else {
                        self.posts = []
                    }
                }
            } catch {
                await MainActor.run {
                    self.isMemberOfSelectedGroup = false
                    self.posts = []
                }
            }
        }
    }

    private func fetchPostsForGroup(groupID: String) {
        DIContainer.shared.postRepository.fetchPostsForGroup(groupID: groupID)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    AppLog.community.error("Failed to fetch posts: \(error.localizedDescription, privacy: .public)")
                }
            } receiveValue: { fetchedPosts in
                self.posts = fetchedPosts
            }
            .store(in: &cancellables)
    }

    private func savePostToFirebase(post: CommunityPost) {
        Task {
            do {
                try await DIContainer.shared.postRepository.savePost(post: post)
            } catch {
                AppLog.community.error("Failed to save post: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func joinGroup(groupID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        groupService.joinGroup(userID: userID, groupID: groupID) { error in
            if error != nil {
            } else {
                isMemberOfSelectedGroup = true
                fetchPostsForGroup(groupID: groupID)
            }
        }
    }
}

// IMPORTANT:
// The definitions for 'PostRowView' and 'CommentsView' are NOT included below.
// Please ensure you have these structs defined in their own separate files
// (e.g., PostRowView.swift and CommentsView.swift) and that these files
// are correctly included in your app's target.
