! Copyright (c) 2024 Vaughan Kitchen
! Minimalistic BM25 search engine.

module vocab_mod
        implicit none
        private

        ! Fortran doesn't allow array of pointers
        type :: item
                character(len=:), allocatable :: term
                integer :: where, size
        end type item


        type, public :: vocab_class
                integer :: capacity, length
                type(item), allocatable :: store(:)
        contains
                procedure, public :: init => vocab_init
                procedure, private :: expand => vocab_expand
                procedure, public :: add => vocab_add
                procedure, public :: get => vocab_get
                procedure, public :: print => vocab_print
        end type vocab_class

contains
        ! djb2 hash function from http://www.cse.yorku.ca/~oz/hash.html
        function hash(str, cap) result(out)
                character(len=*), intent(in) :: str
                integer, intent(in) :: cap
                integer :: out
                integer :: i

                out = 5381

                do i = 1, len(str)
                        out = mod(ishft(out, 5) + out + ichar(str(i:i)), cap) ! hash * 33 + c
                end do
        end function hash

        subroutine vocab_init(this)
                class(vocab_class) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(this%capacity))
        end subroutine vocab_init

        subroutine vocab_expand(this)
                class(vocab_class), intent(inout) :: this
                type(item), allocatable :: buffer(:)
                integer :: old_cap, i, j

                old_cap = this%capacity
                this%capacity = this%capacity * 2

                call move_alloc(this%store, buffer)
                allocate(this%store(this%capacity))

                do i = 1, old_cap
                        if (.NOT. allocated(buffer(i)%term)) cycle

                        j = hash(buffer(i)%term, this%capacity)

                        do while (allocated(this%store(j+1)%term))
                                j = mod(j + 1, this%capacity)
                        end do

                        this%store(j+1) = buffer(i)
                end do

                deallocate(buffer)
        end subroutine vocab_expand

        subroutine vocab_add(this, term, where, size)
                class(vocab_class), intent(inout) :: this
                character(len=*), intent(in) :: term
                integer, intent(in) :: where, size
                integer :: i

                if (this%length * 2 > this%capacity) call this%expand()

                i = hash(term, this%capacity)

                do while (allocated(this%store(i+1)%term))
                        i = mod(i + 1, this%capacity)
                end do

                this%store(i+1)%term = term
                this%store(i+1)%where = where
                this%store(i+1)%size = size

                this%length = this%length + 1
        end subroutine vocab_add

        subroutine vocab_get(this, rc, term, where, size)
                class(vocab_class), intent(inout) :: this
                character(len=*), intent(in) :: term
                integer, intent(inout) :: rc, where, size
                integer :: i

                rc = 0
                i = hash(term, this%capacity)

                do while (allocated(this%store(i+1)%term))
                        if (term == this%store(i+1)%term) then
                                where = this%store(i+1)%where
                                size = this%store(i+1)%size
                                return
                        end if
                        i = mod(i + 1, this%capacity)
                end do

                rc = 1
        end subroutine vocab_get

        subroutine vocab_print(this)
                class(vocab_class), intent(inout) :: this
                integer :: i

                do i = 1, this%capacity
                        if (allocated(this%store(i)%term)) then
                                print *, this%store(i)%term, this%store(i)%where, this%store(i)%size
                        end if
                end do
        end subroutine vocab_print
end module vocab_mod

program index
        use vocab_mod
        implicit none

        integer, allocatable :: length_vector(:)
        character(len=255), allocatable :: primary_keys(:)
        type(vocab_class) :: vocab
        character(len=1024) :: buffer
        character(len=255) :: query(10) ! maximum query size is 10 terms
        integer :: file_size, string_length, postings_where, postings_size, no_terms, query_id, query_start, i
        character(len=1) :: string_length_raw
        real :: average_document_length
        integer :: rc ! return code

        ! Read the document lengths
        open (unit=10, action='read', file='lengths.bin', iostat=rc, access='stream', form='unformatted')
        if (rc /= 0) stop 'ERROR: open failed'
        inquire (unit=10, size=file_size)
        allocate(length_vector(file_size / 4))
        read (10) length_vector
        close (10)

        ! Compute the average document length for BM25
        average_document_length = real(sum(length_vector)) / real(size(length_vector))

        ! Read the primary_keys
        allocate(primary_keys(size(length_vector)))
        open (unit=10, action='read', file='docids.bin', iostat=rc)
        if (rc /= 0) stop 'ERROR: open failed'
        do i = 1, size(length_vector)
                read (10, '(A)', iostat=rc) primary_keys(i)
                if (rc /= 0) stop 'ERROR: read failed'
        end do
        close (10)

        ! Build the vocabulary in memory
        call vocab%init()
        open (unit=10, action='read', file='vocab.bin', iostat=rc, access='stream', form='unformatted')
        if (rc /= 0) stop 'ERROR: open failed'
        do
                read (10, iostat=rc) string_length_raw
                if (is_iostat_end(rc)) exit
                string_length = ichar(string_length_raw(1:1))
                read (10) buffer(1:string_length), string_length_raw, postings_where, postings_size
                call vocab%add(buffer(1:string_length), postings_where, postings_size)
        end do
        close (10)

        ! Allocate buffers

        ! Set up the rsv pointers

        ! Search (one query per line)
        do
                read (*, '(A)', iostat=rc) buffer
                if (is_iostat_end(rc)) exit
                no_terms = 1
                do
                        ! Try read n terms from the query
                        read (buffer, *, iostat=rc) query(1:1+no_terms)
                        ! If the query is fully consumed we have succeeded
                        if (rc /= 0) exit
                        ! Else increase n and try again
                        no_terms = no_terms + 1
                end do

                query_start = 1
                query_id = 0
                read (buffer, *, iostat=rc) query_id
                if (rc == 0) query_start = 2

                do i = query_start, no_terms
                        call vocab%get(rc, trim(query(i)), postings_where, postings_size)
                        if (rc /= 0) cycle
                        print *, postings_where, postings_size
                end do
        end do

end program index
