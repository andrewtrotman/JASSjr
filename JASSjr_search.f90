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

program search
        use vocab_mod
        implicit none

        ! Literals are 32-bit unless type specified which can only be done with a custom type
        ! Here 15 refers to significant decimal digits which requires double precision
        integer, parameter :: dp = selected_real_kind(15)

        real(kind=8) :: k1 = 0.9_dp ! BM25 k1 parameter
        real(kind=8) :: b = 0.4_dp ! BM25 b parameter

        integer, allocatable :: length_vector(:)
        integer, allocatable :: postings(:)
        real(kind=8), allocatable :: rsv(:)
        integer, allocatable :: rsv_pointers(:)
        character(len=255), allocatable :: primary_keys(:)
        type(vocab_class) :: vocab
        character(len=1024) :: buffer
        character(len=255) :: query(10) ! maximum query size is 10 terms
        integer :: file_size, string_length, postings_where, postings_size, no_terms, query_id, query_start, docid, i, j
        character(len=1) :: string_length_raw
        real(kind=8) :: average_document_length, tf, idf
        integer :: rc ! return code

        ! Read the document lengths
        open (unit=10, action='read', file='lengths.bin', iostat=rc, access='stream', form='unformatted')
        if (rc /= 0) stop 'ERROR: open failed'
        inquire (unit=10, size=file_size)
        allocate(length_vector(file_size / 4))
        read (10) length_vector
        close (10)

        ! Compute the average document length for BM25
        average_document_length = real(sum(length_vector), 8) / real(size(length_vector), 8)

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

        ! Open the postings list file
        open (unit=10, action='read', file='postings.bin', iostat=rc, access='stream', form='unformatted')
        if (rc /= 0) stop 'ERROR: open failed'

        ! Allocate buffers
        allocate(postings(size(length_vector) * 2))

        ! Set up the rsv pointers
        allocate(rsv(size(length_vector)))
        allocate(rsv_pointers(size(length_vector)))

        do i = 1, size(rsv_pointers)
                rsv_pointers(i) = i
        end do

        ! Search (one query per line)
        do
                read (*, '(A)', iostat=rc) buffer
                if (is_iostat_end(rc)) exit

                ! Zero the accumulator array
                rsv = 0

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

                        read (10, pos=postings_where+1) postings ! TODO limit postings read

                        idf = log(real(size(primary_keys), 8) / real(postings_size / 8, 8))

                        do j = 1, postings_size / 4, 2
                                docid = postings(j) + 1
                                tf = postings(j+1)
                                rsv(docid) = rsv(docid) + idf * (tf * (k1 + 1)) &
                                        / (tf + k1 * (1 - b + b * (length_vector(docid) / average_document_length)))
                        end do
                end do

                call sort

                do i = 1, size(rsv_pointers)
                        docid = rsv_pointers(i)
                        if (i == 1001) exit
                        if (.NOT. rsv(docid) .GT. 0) exit

                        ! Many fortran compilers (including gfortran) omit the leading 0 when printing
                        if (rsv(docid) < 1) then
                                print '(I0, 1X, A, 1X, A, 1X, I0, 1X, A, F0.4, 1X, A)' &
                                        , query_id, 'Q0', trim(primary_keys(docid)), i, '0', rsv(docid), 'JASSjr'
                        else
                                print '(I0, 1X, A, 1X, A, 1X, I0, 1X, F0.4, 1X, A)' &
                                        , query_id, 'Q0', trim(primary_keys(docid)), i, rsv(docid), 'JASSjr'
                        end if
                end do
        end do

        close (10)
contains
        subroutine sort
                call quicksort(1, size(rsv_pointers))
        end subroutine sort

        recursive subroutine quicksort(lo, hi)
                integer, intent(in) :: lo, hi

                integer :: pivot, left, right, tmp
                real(kind=8) :: delta = 0.0000000001

                if (.NOT. lo .LT. hi) then
                        return
                end if

                pivot = rsv_pointers((lo + hi) / 2)
                left = lo - 1
                right = hi + 1
                do
                        left = left + 1
                        do while (rsv(rsv_pointers(left)) .GT. rsv(pivot) &
                        .OR. (abs(rsv(rsv_pointers(left)) - rsv(pivot)) .LE. delta .AND. rsv_pointers(left) .GT. pivot))
                                left = left + 1
                        end do
                        right = right - 1
                        do while (rsv(rsv_pointers(right)) .LT. rsv(pivot) &
                        .OR. (abs(rsv(rsv_pointers(right)) - rsv(pivot)) .LE. delta .AND. rsv_pointers(right) .LT. pivot))
                                right = right - 1
                        end do

                        if (left .GE. right) then
                                exit
                        end if

                        tmp = rsv_pointers(left)
                        rsv_pointers(left) = rsv_pointers(right)
                        rsv_pointers(right) = tmp
                end do

                call quicksort(lo, right)
                call quicksort(right + 1, hi)
        end subroutine quicksort
end program search
